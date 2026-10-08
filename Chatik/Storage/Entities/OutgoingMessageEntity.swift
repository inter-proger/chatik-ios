//
//  OutgoingMessageEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о неотправленном сообщении; сырая структура — `OutgoingMessage`. Ключ — `clientId`: в БД лежат
/// сообщения только текущего пользователя (БД очищается при выходе).
@objc(OutgoingMessageEntity)
final class OutgoingMessageEntity: NSManagedObject {
    @NSManaged var clientId: String?
    @NSManaged var conversationId: Int64
    @NSManaged var senderId: Int64
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var status: String?

    static let clientIdKey = "clientId"
    static let createdAtKey = "createdAt"

    /// Запрос всех записей.
    static func makeFetchRequest() -> NSFetchRequest<OutgoingMessageEntity> {
        NSFetchRequest<OutgoingMessageEntity>(entityName: "OutgoingMessageEntity")
    }

    /// Запрос записей с переданными `clientId`.
    /// - Parameter clientIds: идентификаторы искомых записей.
    static func makeFetchRequest(clientIds: [String]) -> NSFetchRequest<OutgoingMessageEntity> {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", clientIdKey, clientIds)
        return request
    }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameter message: источник данных.
    func update(from message: OutgoingMessage) {
        clientId = message.clientId
        conversationId = Int64(message.conversationId)
        senderId = Int64(message.senderId)
        text = message.text
        createdAt = message.createdAt
        status = message.status.rawValue
    }

    /// Удаляет в контексте записи, которые уже подтверждены сервером, не вызывая `save()`.
    /// - Parameters:
    ///   - messages: серверные сообщения; запись удаляется, если совпали и `clientId`, и отправитель.
    ///   - context: фоновый контекст записи.
    static func deleteConfirmed(by messages: [Message], in context: NSManagedObjectContext) throws {
        let keys = Set(messages.map(\.clientKey))
        let request = makeFetchRequest(clientIds: messages.map(\.clientId))
        for entity in try context.fetch(request) {
            guard let clientId = entity.clientId,
                  keys.contains(MessageClientKey(senderId: Int(entity.senderId), clientId: clientId)) else { continue }
            context.delete(entity)
        }
    }
}

extension OutgoingMessage {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи нет обязательных полей или статус неизвестен.
    init?(entity: OutgoingMessageEntity) {
        guard let clientId = entity.clientId,
              let text = entity.text,
              let createdAt = entity.createdAt,
              let status = entity.status.flatMap(OutgoingMessageStatus.init(rawValue:)) else { return nil }
        self.init(
            clientId: clientId,
            conversationId: Int(entity.conversationId),
            senderId: Int(entity.senderId),
            text: text,
            createdAt: createdAt,
            status: status
        )
    }
}
