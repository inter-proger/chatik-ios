//
//  MessageEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о сообщении; сырая структура — `Message`. Отправитель хранится только как id,
/// сами пользователи — в кэше пользователей.
@objc(MessageEntity)
final class MessageEntity: NSManagedObject, StorageEntity {
    @NSManaged var messageId: Int64
    @NSManaged var conversationId: Int64
    @NSManaged var blockId: Int64
    @NSManaged var senderId: Int64
    @NSManaged var type: String?
    @NSManaged var text: String?
    @NSManaged var isEdited: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?

    static let idKey = "messageId"
    static let conversationIdKey = "conversationId"

    var storageId: Int { Int(messageId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameter message: источник данных.
    func update(from message: Message) {
        messageId = Int64(message.messageId)
        conversationId = Int64(message.conversationId)
        blockId = Int64(message.blockId)
        senderId = Int64(message.senderId)
        type = message.type.rawValue
        text = message.text
        isEdited = message.isEdited
        createdAt = message.createdAt
        updatedAt = message.updatedAt
    }

    /// Сохраняет сообщения в контексте (upsert по `messageId`), не вызывая `save()`.
    /// - Parameters:
    ///   - messages: сырые структуры сообщений.
    ///   - context: фоновый контекст записи.
    static func upsert(_ messages: [Message], in context: NSManagedObjectContext) throws {
        _ = try upsert(messages, id: \.messageId, in: context) { entity, message in entity.update(from: message) }
    }
}

extension Message {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи нет обязательных полей.
    init?(entity: MessageEntity) {
        guard let rawType = entity.type,
              let text = entity.text,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else { return nil }
        self.init(
            messageId: Int(entity.messageId),
            conversationId: Int(entity.conversationId),
            blockId: Int(entity.blockId),
            senderId: Int(entity.senderId),
            type: MessageType(rawValue: rawType) ?? .unknown,
            text: text,
            isEdited: entity.isEdited,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
