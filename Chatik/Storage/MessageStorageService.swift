//
//  MessageStorageService.swift
//  Chatik
//

import CoreData

/// Чтение кэша сообщений. Его получает и лента переписки (`MessagesListService`): читать БД может кто угодно,
/// писать — только `MessageCacheService`.
protocol MessageStorageReading: Sendable {
    /// Состояние кэша переписки; `nil` — кэша нет.
    func fetchState(conversationId: Int) async throws -> MessageCacheState?
    /// Самые новые сообщения переписки целыми блоками — не меньше `minCount`, если столько есть; сначала самые новые.
    func fetchLatestBlocks(conversationId: Int, minCount: Int) async throws -> [Message]
    /// Сообщения блоков старше `beforeBlockId` тем же правилом.
    func fetchBlocks(conversationId: Int, olderThan beforeBlockId: Int, minCount: Int) async throws -> [Message]
    /// Сообщения начиная с блока `fromBlockId` и новее, сначала самые новые.
    func fetchMessages(conversationId: Int, fromBlockId: Int) async throws -> [Message]
    /// Какие из `blockIds` есть в кэше переписки (хотя бы одним сообщением).
    func cachedBlockIds(conversationId: Int, among blockIds: [Int]) async throws -> Set<Int>
}

/// Запись кэша сообщений — только для `MessageCacheService`: один писатель — один порядок записей.
protocol MessageStorageWriting: Sendable {
    /// Применяет изменения одной транзакцией.
    /// - Returns: версии сообщений из `upserts` и найденных `updatesOfExisting`, оставшиеся в БД после слияния.
    func write(_ changes: MessageStorageChanges) async throws -> [Message]
}

/// Изменение состояния кэша одной переписки.
struct MessageCacheStateChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Записать состояние целиком (сброс кэша).
        case replace(MessageCacheState)
        /// Сдвинуть `syncMark` до максимума с меткой, если состояние есть.
        case advanceSyncMark(ServerTime)
        /// Продолжение подгрузки после более старой страницы, если состояние есть.
        case setPagination(nextBlockId: Int?, hasMorePages: Bool)
    }

    let conversationId: Int
    let kind: Kind
}

/// Что записать в БД одной транзакцией. Решения о том, что писать, принимает `MessageCacheService`; хранилище
/// только применяет.
struct MessageStorageChanges: Sendable {
    /// Upsert по `messageId`: из двух версий побеждает больший `updatedAt`.
    var upserts: [Message] = []
    /// Обновить тем же правилом только сообщения, которые уже есть в БД; отсутствующие не создаются.
    var updatesOfExisting: [Message] = []
    /// Блоки целиком: сообщения блока, которых нет в его списке, удаляются (кроме `protectedMessageIds`),
    /// остальные — upsert.
    var replacedBlocks: [MessageBlock] = []
    /// Переписка, кэш которой заменяется: её сообщения, которых нет в `upserts`, удаляются
    /// (кроме `protectedMessageIds`).
    var replacedConversationId: Int?
    /// Сообщения, которые нельзя удалять при замене блоков и переписки.
    var protectedMessageIds: Set<Int> = []
    /// Серверные сообщения, неотправленные копии которых удаляются из очереди отправки.
    var confirmed: [Message] = []
    /// Изменения состояния кэша в порядке применения.
    var stateChanges: [MessageCacheStateChange] = []

    var isEmpty: Bool {
        upserts.isEmpty && updatesOfExisting.isEmpty && replacedBlocks.isEmpty && replacedConversationId == nil
            && confirmed.isEmpty && stateChanges.isEmpty
    }
}

/// Хранилище сообщений в CoreData — чтобы переписку можно было открыть без сети — и состояния их кэша
/// (`MessageCacheStateEntity`). Все операции выполняются в фоновых контекстах.
///
/// Серверное сообщение с тем же отправителем и `clientId`, что у неотправленного (`OutgoingMessageEntity`), —
/// подтверждение его доставки: неотправленная копия удаляется в той же транзакции (`confirmed`).
///
/// `@unchecked Sendable`: единственное состояние — источник контейнера, который используется только через
/// `performBackgroundTask`, безопасный для вызова из любого потока.
final class MessageStorageService: MessageStorageReading, MessageStorageWriting, @unchecked Sendable {
    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    // MARK: - Запись

    /// Применяет изменения одной транзакцией: сначала удаления при замене переписки и блоков, затем upsert,
    /// обновления, удаление неотправленных копий и состояние кэша.
    /// - Parameter changes: изменения.
    /// - Returns: версии сообщений из `upserts` и найденных `updatesOfExisting` после слияния.
    func write(_ changes: MessageStorageChanges) async throws -> [Message] {
        guard !changes.isEmpty else { return [] }
        return try await container.performWrite { context in
            try Self.deleteReplaced(changes, in: context)
            let blockMessages = changes.replacedBlocks.flatMap(\.messages)
            try MessageEntity.upsert(blockMessages, in: context)
            let upserted = try MessageEntity.upsert(changes.upserts, in: context)
            let updated = try MessageEntity.updateExisting(changes.updatesOfExisting, in: context)
            try OutgoingMessageEntity.deleteConfirmed(by: changes.confirmed, in: context)
            try changes.stateChanges.forEach { try Self.apply($0, in: context) }
            let written = (changes.upserts + changes.updatesOfExisting).compactMap { message in
                (upserted[message.messageId] ?? updated[message.messageId]).flatMap(Message.init(entity:))
            }
            try context.save()
            return written
        }
    }

    /// Удаляет сообщения, вытесненные заменой переписки и блоков; защищённые и пришедшие в той же записи остаются.
    /// - Parameters:
    ///   - changes: изменения.
    ///   - context: фоновый контекст записи.
    private static func deleteReplaced(_ changes: MessageStorageChanges, in context: NSManagedObjectContext) throws {
        if let conversationId = changes.replacedConversationId {
            let kept = changes.protectedMessageIds.union(changes.upserts.map(\.messageId))
            try deleteMessages(conversationId: conversationId, blockId: nil, keeping: kept, in: context)
        }
        for block in changes.replacedBlocks {
            let kept = changes.protectedMessageIds.union(block.messages.map(\.messageId))
            try deleteMessages(conversationId: block.conversationId, blockId: block.blockId, keeping: kept, in: context)
        }
    }

    /// Удаляет сообщения переписки (или одного её блока), кроме перечисленных.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - blockId: блок; `nil` — вся переписка.
    ///   - kept: сообщения, которые остаются.
    ///   - context: фоновый контекст записи.
    private static func deleteMessages(
        conversationId: Int,
        blockId: Int?,
        keeping kept: Set<Int>,
        in context: NSManagedObjectContext
    ) throws {
        var predicates = [
            NSPredicate(format: "%K == %lld", MessageEntity.conversationIdKey, Int64(conversationId)),
            NSPredicate(format: "NOT (%K IN %@)", MessageEntity.idKey, kept.map { Int64($0) }),
        ]
        if let blockId {
            predicates.append(NSPredicate(format: "%K == %lld", MessageEntity.blockIdKey, Int64(blockId)))
        }
        let request = MessageEntity.makeFetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        try context.fetch(request).forEach(context.delete)
    }

    /// Применяет изменение состояния кэша, не вызывая `save()`. Сдвиг отметки и пагинация без записи состояния
    /// ничего не делают: переписка без кэша остаётся без кэша.
    /// - Parameters:
    ///   - change: изменение.
    ///   - context: фоновый контекст записи.
    private static func apply(_ change: MessageCacheStateChange, in context: NSManagedObjectContext) throws {
        let entity = try context.fetch(MessageCacheStateEntity.makeFetchRequest(id: change.conversationId)).first
        switch change.kind {
        case let .replace(state):
            (entity ?? MessageCacheStateEntity(context: context)).update(from: state, conversationId: change.conversationId)
        case let .advanceSyncMark(mark):
            guard let entity, entity.syncMark < mark.milliseconds else { return }
            entity.syncMark = mark.milliseconds
        case let .setPagination(nextBlockId, hasMorePages):
            guard let entity else { return }
            entity.nextBlockId = nextBlockId.map { NSNumber(value: Int64($0)) }
            entity.hasMorePages = hasMorePages
        }
    }

    // MARK: - Чтение

    /// Состояние кэша переписки.
    /// - Parameter conversationId: переписка.
    func fetchState(conversationId: Int) async throws -> MessageCacheState? {
        try await container.performRead { context in
            try context.fetch(MessageCacheStateEntity.makeFetchRequest(id: conversationId)).first
                .map(MessageCacheState.init(entity:))
        }
    }

    /// Самые новые сообщения переписки целыми блоками.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - minCount: сколько сообщений прочитать как минимум; последний блок дочитывается целиком.
    func fetchLatestBlocks(conversationId: Int, minCount: Int) async throws -> [Message] {
        try await container.performRead { context in
            try Self.fetchWholeBlocks(conversationId: conversationId, olderThan: nil, minCount: minCount, in: context)
        }
    }

    /// Сообщения блоков старше `beforeBlockId` целыми блоками.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - beforeBlockId: самый старый уже прочитанный блок.
    ///   - minCount: сколько сообщений прочитать как минимум; последний блок дочитывается целиком.
    func fetchBlocks(conversationId: Int, olderThan beforeBlockId: Int, minCount: Int) async throws -> [Message] {
        try await container.performRead { context in
            try Self.fetchWholeBlocks(conversationId: conversationId, olderThan: beforeBlockId, minCount: minCount, in: context)
        }
    }

    /// Сообщения начиная с блока `fromBlockId` и новее.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - fromBlockId: самый старый блок, который нужен.
    func fetchMessages(conversationId: Int, fromBlockId: Int) async throws -> [Message] {
        try await container.performRead { context in
            let request = MessageEntity.makeFetchRequest()
            request.predicate = NSPredicate(
                format: "%K == %lld AND %K >= %lld",
                MessageEntity.conversationIdKey, Int64(conversationId), MessageEntity.blockIdKey, Int64(fromBlockId)
            )
            request.sortDescriptors = [NSSortDescriptor(key: MessageEntity.idKey, ascending: false)]
            return try context.fetch(request).compactMap(Message.init(entity:))
        }
    }

    /// Какие из `blockIds` есть в кэше переписки.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - blockIds: проверяемые блоки.
    func cachedBlockIds(conversationId: Int, among blockIds: [Int]) async throws -> Set<Int> {
        guard !blockIds.isEmpty else { return [] }
        return try await container.performRead { context in
            let request = NSFetchRequest<NSDictionary>(entityName: String(describing: MessageEntity.self))
            request.predicate = NSPredicate(
                format: "%K == %lld AND %K IN %@",
                MessageEntity.conversationIdKey, Int64(conversationId), MessageEntity.blockIdKey, blockIds.map { Int64($0) }
            )
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = [MessageEntity.blockIdKey]
            request.returnsDistinctResults = true
            let rows = try context.fetch(request)
            return Set(rows.compactMap { ($0[MessageEntity.blockIdKey] as? NSNumber)?.intValue })
        }
    }

    /// Читает не меньше `minCount` самых новых сообщений (старше `beforeBlockId`, если он задан) и дочитывает
    /// последний затронутый блок целиком — окно ленты всегда состоит из целых блоков.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - beforeBlockId: читать только блоки старше этого; `nil` — с самого нового.
    ///   - minCount: сколько сообщений прочитать как минимум.
    ///   - context: фоновый контекст чтения.
    /// - Returns: сообщения, сначала самые новые.
    private static func fetchWholeBlocks(
        conversationId: Int,
        olderThan beforeBlockId: Int?,
        minCount: Int,
        in context: NSManagedObjectContext
    ) throws -> [Message] {
        let request = makeBlocksRequest(conversationId: conversationId, olderThan: beforeBlockId)
        request.fetchLimit = minCount
        let head = try context.fetch(request)
        guard head.count == minCount, let last = head.last else { return head.compactMap(Message.init(entity:)) }
        let rest = makeBlocksRequest(conversationId: conversationId, olderThan: nil)
        rest.predicate = NSPredicate(
            format: "%K == %lld AND %K == %lld AND %K < %lld",
            MessageEntity.conversationIdKey, Int64(conversationId),
            MessageEntity.blockIdKey, last.blockId,
            MessageEntity.idKey, last.messageId
        )
        return (head + (try context.fetch(rest))).compactMap(Message.init(entity:))
    }

    /// Запрос сообщений переписки по убыванию блока и `messageId`.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - beforeBlockId: только блоки старше этого; `nil` — все.
    private static func makeBlocksRequest(conversationId: Int, olderThan beforeBlockId: Int?) -> NSFetchRequest<MessageEntity> {
        let request = MessageEntity.makeFetchRequest()
        request.predicate = beforeBlockId.map { blockId in
            NSPredicate(
                format: "%K == %lld AND %K < %lld",
                MessageEntity.conversationIdKey, Int64(conversationId), MessageEntity.blockIdKey, Int64(blockId)
            )
        } ?? NSPredicate(format: "%K == %lld", MessageEntity.conversationIdKey, Int64(conversationId))
        request.sortDescriptors = [
            NSSortDescriptor(key: MessageEntity.blockIdKey, ascending: false),
            NSSortDescriptor(key: MessageEntity.idKey, ascending: false),
        ]
        return request
    }
}
