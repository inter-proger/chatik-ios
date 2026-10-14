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
    @NSManaged var clientId: String?
    @NSManaged var conversationId: Int64
    @NSManaged var blockId: Int64
    @NSManaged var senderId: Int64
    @NSManaged var type: String?
    @NSManaged var text: String?
    @NSManaged var isEdited: Bool
    /// `createdAt` и `updatedAt` в миллисекундах. Имена отличаются от прежних атрибутов типа `Date` намеренно:
    /// смену типа атрибута лёгкая миграция не выводит, а удаление и добавление — выводит.
    @NSManaged var createdAtMs: Int64
    @NSManaged var updatedAtMs: Int64

    static let idKey = "messageId"
    static let conversationIdKey = "conversationId"

    var storageId: Int { Int(messageId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameter message: источник данных.
    func update(from message: Message) {
        messageId = Int64(message.messageId)
        clientId = message.clientId
        conversationId = Int64(message.conversationId)
        blockId = Int64(message.blockId)
        senderId = Int64(message.senderId)
        type = message.type.rawValue
        text = message.text
        isEdited = message.isEdited
        createdAtMs = message.createdAt.milliseconds
        updatedAtMs = message.updatedAt.milliseconds
    }

    /// `true`, если в записи версия сообщения новее `message`: такую запись перезаписывать нельзя —
    /// событие WebSocket могло прийти раньше ответа REST с более старыми данными.
    /// - Parameter message: версия, которую собираются сохранить.
    func isNewer(than message: Message) -> Bool {
        updatedAtMs > message.updatedAt.milliseconds
    }

    /// Сохраняет сообщения в контексте (upsert по `messageId`), не вызывая `save()`.
    /// Запись, в которой версия новее сохраняемой, не меняется.
    /// - Parameters:
    ///   - messages: сырые структуры сообщений.
    ///   - context: фоновый контекст записи.
    static func upsert(_ messages: [Message], in context: NSManagedObjectContext) throws {
        _ = try upsert(messages, id: \.messageId, in: context) { entity, message in
            guard !entity.isNewer(than: message) else { return }
            entity.update(from: message)
        }
    }
}

extension Message {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи нет обязательных полей. Записи, сохранённые до появления `clientId`,
    ///   тоже отбрасываются — они перезапишутся при следующей загрузке переписки.
    init?(entity: MessageEntity) {
        guard let clientId = entity.clientId,
              let rawType = entity.type,
              let text = entity.text else { return nil }
        self.init(
            messageId: Int(entity.messageId),
            clientId: clientId,
            conversationId: Int(entity.conversationId),
            blockId: Int(entity.blockId),
            senderId: Int(entity.senderId),
            type: MessageType(rawValue: rawType) ?? .unknown,
            text: text,
            isEdited: entity.isEdited,
            createdAt: ServerTime(milliseconds: entity.createdAtMs),
            updatedAt: ServerTime(milliseconds: entity.updatedAtMs)
        )
    }
}
