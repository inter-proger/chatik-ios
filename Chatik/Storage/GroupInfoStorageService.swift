//
//  GroupInfoStorageService.swift
//  Chatik
//

import CoreData

protocol GroupInfoStorageServiceProtocol {
    /// Группы, у которых сохранён состав.
    func fetchConversationIds() async throws -> Set<Int>
    /// Сохранённый состав группы; `nil` — его нет.
    func fetch(conversationId: Int) async throws -> GroupInfo?
    /// Сохраняет состав, если его версия больше сохранённой.
    /// - Parameter createsMissing: `false` — группе без сохранённого состава запись не создаётся.
    func save(_ info: GroupInfo, createsMissing: Bool) async throws
    /// Удаляет состав группы.
    func delete(conversationId: Int) async throws
}

/// Хранилище составов групп (`GroupInfoEntity`). Это кэш сервера: при выходе его очищает `LocalStorageCleaner`.
final class GroupInfoStorageService: GroupInfoStorageServiceProtocol {
    private let container: PersistentContainerProvider

    /// - Parameter container: хранилище CoreData.
    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Возвращает группы с сохранённым составом.
    func fetchConversationIds() async throws -> Set<Int> {
        try await container.performRead { context in
            let request = NSFetchRequest<NSDictionary>(entityName: GroupInfoEntity.entityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = [GroupInfoEntity.conversationIdKey]
            let ids = try context.fetch(request).compactMap { ($0[GroupInfoEntity.conversationIdKey] as? NSNumber)?.intValue }
            return Set(ids)
        }
    }

    /// Возвращает сохранённый состав группы; битая запись — `nil`.
    /// - Parameter conversationId: группа.
    func fetch(conversationId: Int) async throws -> GroupInfo? {
        try await container.performRead { context in
            try context.fetch(GroupInfoEntity.makeFetchRequest(conversationId: conversationId)).first.flatMap(GroupInfo.init(entity:))
        }
    }

    /// Сохраняет состав (upsert по `conversationId`), если его версия больше сохранённой: поздняя запись старой
    /// версии не откатывает новую.
    /// - Parameters:
    ///   - info: состав группы.
    ///   - createsMissing: создавать ли запись группе, у которой её нет.
    func save(_ info: GroupInfo, createsMissing: Bool) async throws {
        try await container.performWrite { context in
            let existing = try context.fetch(GroupInfoEntity.makeFetchRequest(conversationId: info.conversationId)).first
            guard existing != nil || createsMissing else { return }
            guard existing.map({ Int($0.version) < info.version || GroupInfo(entity: $0) == nil }) ?? true else { return }
            let entity = existing ?? GroupInfoEntity(context: context)
            entity.update(from: info)
            try context.save()
        }
    }

    /// Удаляет состав группы; записи нет — ничего не делает.
    /// - Parameter conversationId: группа.
    func delete(conversationId: Int) async throws {
        try await container.performWrite { context in
            try context.fetch(GroupInfoEntity.makeFetchRequest(conversationId: conversationId)).forEach(context.delete)
            try context.save()
        }
    }
}
