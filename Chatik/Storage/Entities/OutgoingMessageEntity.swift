//
//  OutgoingMessageEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о неотправленном сообщении; сырая структура — `OutgoingMessage`. Ключ — пара `senderId` и `clientId`:
/// очередь переживает выход из аккаунта (`LocalStorageCleaner` её не удаляет), и сообщения пользователей
/// на устройстве разделяет ключ, а не очистка.
@objc(OutgoingMessageEntity)
final class OutgoingMessageEntity: NSManagedObject {
    @NSManaged var clientId: String?
    @NSManaged var conversationId: Int64
    @NSManaged var senderId: Int64
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var status: String?

    static let entityName = "OutgoingMessageEntity"
    static let clientIdKey = "clientId"
    static let senderIdKey = "senderId"
    static let createdAtKey = "createdAt"

    /// Запрос всех записей.
    static func makeFetchRequest() -> NSFetchRequest<OutgoingMessageEntity> {
        NSFetchRequest<OutgoingMessageEntity>(entityName: entityName)
    }

    /// Запрос записей отправителя, сначала самые старые.
    /// - Parameter senderId: отправитель.
    static func makeFetchRequest(senderId: Int) -> NSFetchRequest<OutgoingMessageEntity> {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "%K == %lld", senderIdKey, Int64(senderId))
        request.sortDescriptors = [NSSortDescriptor(key: createdAtKey, ascending: true)]
        return request
    }

    /// Запрос записей с переданными `clientId` любых отправителей. Один `IN`, а не OR по парам ключа: размер
    /// предиката не растёт с числом записей (у SQLite есть предел глубины выражения), отправителя сверяет
    /// `fetchEntitiesByKey(keys:in:)`.
    /// - Parameter clientIds: идентификаторы искомых записей.
    static func makeFetchRequest(clientIds: [String]) -> NSFetchRequest<OutgoingMessageEntity> {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", clientIdKey, clientIds)
        return request
    }

    /// Достаёт одним запросом записи с переданными ключами: совпадают и отправитель, и `clientId`.
    /// - Parameters:
    ///   - keys: ключи искомых записей.
    ///   - context: контекст, в котором выполняется запрос.
    /// - Returns: словарь `ключ → Entity`.
    static func fetchEntitiesByKey(
        keys: [MessageClientKey],
        in context: NSManagedObjectContext
    ) throws -> [MessageClientKey: OutgoingMessageEntity] {
        guard !keys.isEmpty else { return [:] }
        let wanted = Set(keys)
        let pairs = try context.fetch(makeFetchRequest(clientIds: Array(Set(keys.map(\.clientId))))).compactMap { entity in
            entity.clientKey.flatMap { wanted.contains($0) ? ($0, entity) : nil }
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// Ключ записи; `nil` — в записи нет `clientId`.
    var clientKey: MessageClientKey? {
        clientId.map { MessageClientKey(senderId: Int(senderId), clientId: $0) }
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
        for entity in try fetchEntitiesByKey(keys: messages.map(\.clientKey), in: context).values {
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
