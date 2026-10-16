//
//  OutgoingMessageStorageService.swift
//  Chatik
//

import CoreData

protocol OutgoingMessageStorageServiceProtocol {
    /// Сохраняет сообщение очереди: upsert по `senderId` и `clientId`.
    func save(message: OutgoingMessage) async throws
    /// Сохраняет сообщения очереди одной записью: upsert по `senderId` и `clientId`.
    func save(messages: [OutgoingMessage]) async throws
    /// Сообщения очереди пользователя во всех переписках, сначала самые старые.
    func fetchAll(senderId: Int) async throws -> [OutgoingMessage]
    /// Удаляет сообщение очереди, если оно найдено.
    func delete(senderId: Int, clientId: String) async throws
    /// Удаляет сообщения очереди всех пользователей, созданные раньше `date`.
    func deleteAll(createdBefore date: Date) async throws
}

/// Хранилище очереди отправки в CoreData: сообщения, которые пользователь отправил, а сервер ещё не подтвердил.
/// Очередь переживает выход из аккаунта; сообщения пользователей разделяет ключ записи `(senderId, clientId)`.
/// Подтверждённые сообщения удаляет отсюда `MessageStorageService` при сохранении серверной версии.
final class OutgoingMessageStorageService: OutgoingMessageStorageServiceProtocol {
    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Сохраняет сообщение очереди: обновляет запись с тем же `senderId` и `clientId` (например, статус) или
    /// создаёт новую.
    /// - Parameter message: сырая структура сообщения.
    func save(message: OutgoingMessage) async throws {
        try await save(messages: [message])
    }

    /// Сохраняет сообщения очереди в одном фоновом контексте с одним `save()`: существующие записи (тот же
    /// `senderId` и `clientId`) обновляются, остальные создаются.
    /// - Parameter messages: сырые структуры; повторы ключа внутри списка схлопываются в последнюю версию.
    func save(messages: [OutgoingMessage]) async throws {
        guard !messages.isEmpty else { return }
        try await container.performWrite { context in
            var entitiesByKey = try OutgoingMessageEntity.fetchEntitiesByKey(keys: messages.map(\.clientKey), in: context)
            for message in messages {
                let entity = entitiesByKey[message.clientKey] ?? OutgoingMessageEntity(context: context)
                entity.update(from: message)
                entitiesByKey[message.clientKey] = entity
            }
            try context.save()
        }
    }

    /// Возвращает сообщения очереди пользователя в порядке отправки. Записи с битыми данными пропускаются.
    /// - Parameter senderId: отправитель.
    func fetchAll(senderId: Int) async throws -> [OutgoingMessage] {
        try await container.performRead { context in
            try context.fetch(OutgoingMessageEntity.makeFetchRequest(senderId: senderId)).compactMap(OutgoingMessage.init(entity:))
        }
    }

    /// Удаляет сообщение очереди.
    /// - Parameters:
    ///   - senderId: отправитель.
    ///   - clientId: идентификатор удаляемого сообщения.
    func delete(senderId: Int, clientId: String) async throws {
        let key = MessageClientKey(senderId: senderId, clientId: clientId)
        try await container.performWrite { context in
            for entity in try OutgoingMessageEntity.fetchEntitiesByKey(keys: [key], in: context).values {
                context.delete(entity)
            }
            try context.save()
        }
    }

    /// Удаляет сообщения очереди всех пользователей с `createdAt` раньше `date` одним пакетным запросом, не загружая
    /// записи в память. Записи без `createdAt` не трогаются: дата пишется при создании, и такая запись — не
    /// просроченное сообщение, а неизвестное состояние (при чтении она всё равно пропускается). Сервисы работают
    /// через короткоживущие фоновые контексты, поэтому мержить удаление в другие контексты не нужно.
    /// - Parameter date: граница: сообщения, созданные раньше неё, удаляются.
    func deleteAll(createdBefore date: Date) async throws {
        try await container.performWrite { context in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: OutgoingMessageEntity.entityName)
            request.predicate = NSPredicate(format: "%K < %@", OutgoingMessageEntity.createdAtKey, date as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        }
    }
}
