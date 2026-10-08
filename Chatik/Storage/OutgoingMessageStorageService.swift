//
//  OutgoingMessageStorageService.swift
//  Chatik
//

import CoreData

protocol OutgoingMessageStorageServiceProtocol {
    /// Сохраняет неотправленное сообщение (upsert по `clientId`).
    func save(message: OutgoingMessage) async throws
    /// Возвращает неотправленные сообщения всех переписок, сначала самые старые.
    func fetchAll() async throws -> [OutgoingMessage]
    /// Удаляет неотправленное сообщение, если оно найдено.
    func delete(clientId: String) async throws
}

/// Хранилище очереди отправки в CoreData: сообщения, которые пользователь отправил, а сервер ещё не подтвердил.
/// Подтверждённые сообщения удаляет отсюда `MessageStorageService` при сохранении серверной версии.
final class OutgoingMessageStorageService: OutgoingMessageStorageServiceProtocol {
    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Сохраняет неотправленное сообщение: обновляет запись с тем же `clientId` (например, статус) или создаёт новую.
    /// - Parameter message: сырая структура сообщения.
    func save(message: OutgoingMessage) async throws {
        try await container.performWrite { context in
            let existing = try context.fetch(OutgoingMessageEntity.makeFetchRequest(clientIds: [message.clientId])).first
            let entity = existing ?? OutgoingMessageEntity(context: context)
            entity.update(from: message)
            try context.save()
        }
    }

    /// Возвращает неотправленные сообщения всех переписок в порядке отправки. Записи с битыми данными пропускаются.
    func fetchAll() async throws -> [OutgoingMessage] {
        try await container.performRead { context in
            let request = OutgoingMessageEntity.makeFetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: OutgoingMessageEntity.createdAtKey, ascending: true)]
            return try context.fetch(request).compactMap(OutgoingMessage.init(entity:))
        }
    }

    /// Удаляет неотправленное сообщение.
    /// - Parameter clientId: идентификатор удаляемого сообщения.
    func delete(clientId: String) async throws {
        try await container.performWrite { context in
            for entity in try context.fetch(OutgoingMessageEntity.makeFetchRequest(clientIds: [clientId])) {
                context.delete(entity)
            }
            try context.save()
        }
    }
}
