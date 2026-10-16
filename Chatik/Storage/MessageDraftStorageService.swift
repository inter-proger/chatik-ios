//
//  MessageDraftStorageService.swift
//  Chatik
//

import CoreData

/// Изменение черновика одной переписки.
enum MessageDraftChange: Equatable, Sendable {
    /// Записать текст: upsert по `userId` и `conversationId`.
    case save(String)
    /// Удалить черновик, если запись есть.
    case delete
}

protocol MessageDraftStorageServiceProtocol {
    /// Черновики пользователя: `conversationId` → текст.
    func fetchAll(userId: Int) async throws -> [Int: String]
    /// Применяет изменения черновиков пользователя одним фоновым контекстом.
    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws
    /// Удаляет черновики всех пользователей, сохранённые последний раз раньше `date`.
    func deleteAll(updatedBefore date: Date) async throws
}

/// Хранилище черновиков сообщений в CoreData. Черновики — единственные данные БД, которые переживают выход
/// из аккаунта; пользователей разделяет ключ записи `(userId, conversationId)`.
final class MessageDraftStorageService: MessageDraftStorageServiceProtocol {
    private let container: PersistentContainerProvider
    private let now: () -> Date

    /// - Parameters:
    ///   - container: хранилище CoreData.
    ///   - now: текущее время — момент сохранения черновика (`updatedAt`); подменяется в тестах.
    init(container: PersistentContainerProvider, now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.now = now
    }

    /// Возвращает черновики пользователя. Записи без текста пропускаются.
    /// - Parameter userId: пользователь, набравший черновики.
    func fetchAll(userId: Int) async throws -> [Int: String] {
        try await container.performRead { context in
            let pairs = try context.fetch(MessageDraftEntity.makeFetchRequest(userId: userId)).compactMap { entity in
                entity.text.map { (Int(entity.conversationId), $0) }
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Применяет изменения одним `context.save()`: текст обновляет запись с тем же `userId` и `conversationId`
    /// или создаёт новую, удаление убирает запись, если она есть.
    /// - Parameters:
    ///   - changes: изменения по `conversationId`.
    ///   - userId: пользователь, набравший черновики.
    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws {
        guard !changes.isEmpty else { return }
        let now = now()
        try await container.performWrite { context in
            let request = MessageDraftEntity.makeFetchRequest(userId: userId, conversationIds: Array(changes.keys))
            let pairs = try context.fetch(request).map { (Int($0.conversationId), $0) }
            let existing = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            for (conversationId, change) in changes {
                switch change {
                case let .save(text):
                    let entity = existing[conversationId] ?? MessageDraftEntity(context: context)
                    entity.userId = Int64(userId)
                    entity.conversationId = Int64(conversationId)
                    entity.text = text
                    entity.updatedAt = now
                case .delete:
                    if let entity = existing[conversationId] {
                        context.delete(entity)
                    }
                }
            }
            try context.save()
        }
    }

    /// Удаляет черновики всех пользователей с `updatedAt` раньше `date` одним пакетным запросом, не загружая
    /// записи в память. Записи без `updatedAt` не трогаются: дата пишется при каждом сохранении, и такая запись —
    /// не просроченный черновик, а неизвестное состояние. Сервисы работают через короткоживущие фоновые контексты,
    /// поэтому мержить удаление в другие контексты не нужно.
    /// - Parameter date: граница: черновики, сохранённые раньше неё, удаляются.
    func deleteAll(updatedBefore date: Date) async throws {
        try await container.performWrite { context in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: MessageDraftEntity.entityName)
            request.predicate = NSPredicate(format: "%K < %@", MessageDraftEntity.updatedAtKey, date as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        }
    }
}
