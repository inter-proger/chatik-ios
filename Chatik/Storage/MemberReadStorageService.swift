//
//  MemberReadStorageService.swift
//  Chatik
//

import CoreData

/// Изменение указателей прочтения одной переписки. Указатели только растут, поэтому запись сливается с сохранёнными
/// по максимуму, и несколько изменений можно склеить в одно (`merge(_:)`) без потери порядка.
struct MemberReadWrite: Equatable, Sendable {
    /// Указатели участников по `userId`; сливаются с сохранёнными по максимуму.
    var pointers: [Int: Int]
    /// Состав участников из ответа сервера: указатели остальных удаляются. `nil` — состав не меняется.
    var members: Set<Int>?
    /// `false` — запись применяется, только если у переписки уже есть сохранённые указатели: событие для
    /// ненаблюдаемой переписки не создаёт ей мету.
    var createsMissing: Bool

    /// - Parameters:
    ///   - pointers: указатели участников.
    ///   - members: состав участников из ответа; `nil` — не меняется.
    ///   - createsMissing: создавать мету переписке, у которой её нет.
    init(pointers: [Int: Int], members: Set<Int>? = nil, createsMissing: Bool) {
        self.pointers = pointers
        self.members = members
        self.createsMissing = createsMissing
    }

    /// Склеивает с более новым изменением так, будто они применены по очереди: новый состав участников отбрасывает
    /// указатели ушедших, а указатель из события при уже известном составе добавляет участника в состав.
    /// - Parameter newer: изменение, пришедшее позже.
    mutating func merge(_ newer: MemberReadWrite) {
        if let newMembers = newer.members {
            pointers = pointers.filter { newMembers.contains($0.key) }
            members = newMembers
        } else if members != nil {
            members?.formUnion(newer.pointers.keys)
        }
        pointers.merge(newer.pointers, uniquingKeysWith: max)
        createsMissing = createsMissing || newer.createsMissing
    }
}

protocol MemberReadStorageServiceProtocol {
    /// Переписки, у которых есть сохранённые указатели.
    func fetchConversationIds() async throws -> Set<Int>
    /// Сохранённые указатели переписки по `userId`; `nil` — меты переписки нет.
    func fetchPointers(conversationId: Int) async throws -> [Int: Int]?
    /// Применяет изменения нескольких переписок одним фоновым контекстом.
    func apply(_ writes: [Int: MemberReadWrite]) async throws
    /// Удаляет указатели переписки.
    func delete(conversationId: Int) async throws
}

/// Хранилище указателей прочтения других участников (`MemberReadEntity`). Это кэш сервера: при выходе из аккаунта
/// его очищает `LocalStorageCleaner`.
final class MemberReadStorageService: MemberReadStorageServiceProtocol {
    private let container: PersistentContainerProvider

    /// - Parameter container: хранилище CoreData.
    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Возвращает переписки, у которых есть хотя бы один сохранённый указатель.
    func fetchConversationIds() async throws -> Set<Int> {
        try await container.performRead { context in
            let request = NSFetchRequest<NSDictionary>(entityName: MemberReadEntity.entityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = [MemberReadEntity.conversationIdKey]
            request.returnsDistinctResults = true
            let ids = try context.fetch(request).compactMap { ($0[MemberReadEntity.conversationIdKey] as? NSNumber)?.intValue }
            return Set(ids)
        }
    }

    /// Возвращает сохранённые указатели переписки.
    /// - Parameter conversationId: переписка.
    /// - Returns: `lastReadMessageId` по `userId`; `nil` — у переписки нет ни одного указателя.
    func fetchPointers(conversationId: Int) async throws -> [Int: Int]? {
        try await container.performRead { context in
            let entities = try context.fetch(MemberReadEntity.makeFetchRequest(conversationIds: [conversationId]))
            guard !entities.isEmpty else { return nil }
            let pairs = entities.map { (Int($0.userId), Int($0.lastReadMessageId)) }
            return Dictionary(pairs, uniquingKeysWith: max)
        }
    }

    /// Удаляет все указатели переписки; их нет — ничего не делает.
    /// - Parameter conversationId: переписка.
    func delete(conversationId: Int) async throws {
        try await container.performWrite { context in
            try context.fetch(MemberReadEntity.makeFetchRequest(conversationIds: [conversationId])).forEach(context.delete)
            try context.save()
        }
    }

    /// Применяет изменения одним `context.save()`: указатели сливаются с сохранёнными по максимуму, при известном
    /// составе указатели ушедших участников удаляются. Изменение без `createsMissing` для переписки без сохранённых
    /// указателей пропускается.
    /// - Parameter writes: изменения по `conversationId`.
    func apply(_ writes: [Int: MemberReadWrite]) async throws {
        guard !writes.isEmpty else { return }
        try await container.performWrite { context in
            let entities = try context.fetch(MemberReadEntity.makeFetchRequest(conversationIds: Array(writes.keys)))
            let stored = Dictionary(grouping: entities) { Int($0.conversationId) }
            for (conversationId, write) in writes {
                let existing = stored[conversationId] ?? []
                guard write.createsMissing || !existing.isEmpty else { continue }
                Self.apply(write, conversationId: conversationId, existing: existing, in: context)
            }
            try context.save()
        }
    }

    /// Применяет изменение одной переписки в контексте; `context.save()` не вызывает.
    /// - Parameters:
    ///   - write: изменение.
    ///   - conversationId: переписка.
    ///   - existing: сохранённые указатели переписки.
    ///   - context: фоновый контекст записи.
    private static func apply(
        _ write: MemberReadWrite,
        conversationId: Int,
        existing: [MemberReadEntity],
        in context: NSManagedObjectContext
    ) {
        var entitiesByUser: [Int: MemberReadEntity] = [:]
        for entity in existing {
            let userId = Int(entity.userId)
            guard write.members?.contains(userId) ?? true else {
                context.delete(entity)
                continue
            }
            entitiesByUser[userId] = entity
        }
        for (userId, lastReadMessageId) in write.pointers {
            let entity = entitiesByUser[userId] ?? MemberReadEntity(context: context)
            entity.conversationId = Int64(conversationId)
            entity.userId = Int64(userId)
            entity.lastReadMessageId = max(entity.lastReadMessageId, Int64(lastReadMessageId))
            entitiesByUser[userId] = entity
        }
    }
}
