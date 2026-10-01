//
//  ConversationStorageService.swift
//  Chatik
//

import CoreData

protocol ConversationStorageServiceProtocol {
    /// Сохраняет переписку вместе с аватаром (upsert по `conversationId`).
    func save(conversation: Conversation) async throws
    /// Сохраняет список переписок вместе с аватарами одним фоновым контекстом.
    func save(conversations: [Conversation]) async throws
    /// Сохраняет страницу списка переписок и удаляет из БД переписки, которые пропали с сервера
    /// в покрытом страницей диапазоне.
    func save(page: ConversationsPage, isFirstPage: Bool) async throws
    /// Возвращает все сохранённые переписки, сначала самые новые.
    func fetchAll() async throws -> [Conversation]
    /// Возвращает не больше `limit` самых новых сохранённых переписок.
    func fetchLatest(limit: Int) async throws -> [Conversation]
    /// Ищет переписку по идентификатору.
    func find(byId id: Int) async throws -> Conversation?
    /// Удаляет переписку по идентификатору, если она найдена.
    func delete(byId id: Int) async throws
}

/// Хранилище переписок в CoreData. Переписка сохраняется вместе с аватаром — он попадает в хранилище файлов;
/// собеседник хранится только как id, сами пользователи — в кэше пользователей. Все операции выполняются
/// в фоновых контекстах.
final class ConversationStorageService: ConversationStorageServiceProtocol {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    /// Сохраняет одну переписку: обновляет существующую запись с тем же `conversationId` или создаёт новую.
    /// - Parameter conversation: сырая структура переписки.
    func save(conversation: Conversation) async throws {
        try await save(conversations: [conversation])
    }

    /// Сохраняет список переписок одним фоновым контекстом (upsert по `conversationId`).
    /// - Parameter conversations: сырые структуры; повторы `conversationId` схлопываются в одну запись.
    func save(conversations: [Conversation]) async throws {
        guard !conversations.isEmpty else { return }
        try await container.performWrite { context in
            try ConversationEntity.upsert(conversations, in: context)
            try context.save()
        }
    }

    /// Сохраняет страницу переписок одним фоновым контекстом. Переписки из покрытого страницей диапазона
    /// `conversationId` (см. `ConversationsPage.coveredIdRange`), которых в ней нет, удаляются: на сервере
    /// их больше нет в списке, и после перезапуска они не должны всплыть из кэша.
    /// - Parameters:
    ///   - page: страница из ответа сервера.
    ///   - isFirstPage: `true` — страница первая, выше неё переписок нет.
    func save(page: ConversationsPage, isFirstPage: Bool) async throws {
        let idRange = page.coveredIdRange(isFirstPage: isFirstPage)
        guard !page.conversations.isEmpty || idRange != nil else { return }
        try await container.performWrite { context in
            try ConversationEntity.upsert(page.conversations, in: context)
            if let idRange {
                try Self.deleteMissing(in: idRange, keeping: page.conversations.map(\.conversationId), context: context)
            }
            try context.save()
        }
    }

    /// Возвращает все сохранённые переписки по убыванию `conversationId` — в порядке списка на сервере.
    /// Записи с битыми данными пропускаются.
    func fetchAll() async throws -> [Conversation] {
        try await fetch(limit: nil)
    }

    /// Возвращает самые новые сохранённые переписки — столько, сколько помещается в первую страницу списка:
    /// в БД копится всё, что пользователь когда-либо пролистал, а экрану до ответа сервера нужно только начало.
    /// Записи с битыми данными пропускаются, поэтому переписок может вернуться меньше `limit`.
    /// - Parameter limit: максимальное число переписок.
    func fetchLatest(limit: Int) async throws -> [Conversation] {
        try await fetch(limit: limit)
    }

    /// Выбирает переписки по убыванию `conversationId`, пропуская записи с битыми данными.
    /// - Parameter limit: максимальное число записей; `nil` — без ограничения.
    private func fetch(limit: Int?) async throws -> [Conversation] {
        try await container.performBackgroundTask { context in
            let request = ConversationEntity.makeFetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: ConversationEntity.idKey, ascending: false)]
            request.fetchLimit = limit ?? 0
            return try context.fetch(request).compactMap(Conversation.init(entity:))
        }
    }

    /// Ищет переписку по идентификатору.
    /// - Parameter id: идентификатор искомой переписки.
    func find(byId id: Int) async throws -> Conversation? {
        try await container.performBackgroundTask { context in
            try context.fetch(ConversationEntity.makeFetchRequest(id: id)).first.flatMap(Conversation.init(entity:))
        }
    }

    /// Удаляет переписку по идентификатору. Аватар остаётся в хранилище файлов.
    /// - Parameter id: идентификатор удаляемой переписки.
    func delete(byId id: Int) async throws {
        try await container.performWrite { context in
            guard let entity = try context.fetch(ConversationEntity.makeFetchRequest(id: id)).first else { return }
            context.delete(entity)
            try context.save()
        }
    }

    /// Удаляет переписки из диапазона идентификаторов, кроме перечисленных.
    /// - Parameters:
    ///   - idRange: диапазон `conversationId`, который покрыт актуальными данными.
    ///   - keptIds: переписки, которые есть в актуальных данных и остаются.
    ///   - context: контекст записи; `save()` вызывает владелец.
    private static func deleteMissing(
        in idRange: ClosedRange<Int>,
        keeping keptIds: [Int],
        context: NSManagedObjectContext
    ) throws {
        let request = ConversationEntity.makeFetchRequest()
        request.predicate = NSPredicate(
            format: "%K BETWEEN {%lld, %lld} AND NOT (%K IN %@)",
            ConversationEntity.idKey, Int64(idRange.lowerBound), Int64(idRange.upperBound),
            ConversationEntity.idKey, keptIds.map { Int64($0) }
        )
        try context.fetch(request).forEach(context.delete)
    }
}
