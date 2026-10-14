//
//  ConversationEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о переписке; сырая структура — `Conversation`.
@objc(ConversationEntity)
final class ConversationEntity: NSManagedObject, StorageEntity {
    @NSManaged var conversationId: Int64
    @NSManaged var type: String?
    /// Идентификаторы участников в JSON-массиве.
    @NSManaged var memberIds: Data?
    @NSManaged var name: String?
    @NSManaged var avatar: FileEntity?
    /// Id собеседника; `nil` — собеседника нет (группа).
    @NSManaged var opponentUserId: NSNumber?
    /// Поля `LastMessage`; `lastMessageId == nil` — последнего сообщения нет.
    @NSManaged var lastMessageId: NSNumber?
    @NSManaged var lastMessageType: String?
    @NSManaged var lastMessageText: String?
    /// `LastMessage.updatedAt` в миллисекундах.
    @NSManaged var lastMessageUpdatedAt: NSNumber?
    /// `positionUpdatedAt` в миллисекундах; по нему сортируется список.
    @NSManaged var positionUpdatedAt: Int64
    /// `updatedInfoAt` в миллисекундах.
    @NSManaged var updatedInfoAt: Int64

    static let idKey = "conversationId"
    static let positionKey = "positionUpdatedAt"

    var storageId: Int { Int(conversationId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameters:
    ///   - conversation: источник данных.
    ///   - avatar: уже сохранённая в том же контексте запись аватара группы; `nil` — аватара нет.
    func update(from conversation: Conversation, avatar: FileEntity?) {
        conversationId = Int64(conversation.conversationId)
        type = conversation.type.rawValue
        memberIds = try? JSONEncoder().encode(conversation.memberIds)
        name = conversation.name
        self.avatar = avatar
        opponentUserId = conversation.opponentUserId.map { NSNumber(value: $0) }
        lastMessageId = conversation.lastMessage.map { NSNumber(value: $0.messageId) }
        lastMessageType = conversation.lastMessage?.type.rawValue
        lastMessageText = conversation.lastMessage?.text
        lastMessageUpdatedAt = conversation.lastMessage.map { NSNumber(value: $0.updatedAt.milliseconds) }
        positionUpdatedAt = conversation.positionUpdatedAt.milliseconds
        updatedInfoAt = conversation.updatedInfoAt.milliseconds
    }

    /// Сохраняет переписки вместе с аватарами в контексте (upsert по `conversationId`), не вызывая `save()`.
    /// По умолчанию существующая запись сливается с сохраняемой версией по правилам `ConversationMerger` —
    /// страховка на случай, если в БД окажется версия новее: позиция и информация не откатываются.
    /// - Parameters:
    ///   - conversations: сырые структуры переписок.
    ///   - mergingWithStored: `false` — запись перезаписывается как есть (замена списка целиком).
    ///   - context: фоновый контекст записи.
    static func upsert(_ conversations: [Conversation], mergingWithStored: Bool = true, in context: NSManagedObjectContext) throws {
        let avatarsById = try FileEntity.upsert(conversations.compactMap(\.avatar), in: context)
        _ = try upsert(conversations, id: \.conversationId, in: context) { entity, conversation in
            // У новой записи полей ещё нет, и `init?(entity:)` вернёт `nil` — тогда сливать не с чем.
            let stored = mergingWithStored ? Conversation(entity: entity) : nil
            let merged = stored.map { ConversationMerger.merge(.full(conversation), into: $0)?.conversation ?? $0 } ?? conversation
            // Аватар из сохранённой версии (её информация новее) уже связан с записью — его в `avatarsById` нет.
            entity.update(from: merged, avatar: merged.avatar.flatMap { avatarsById[$0.fileId] ?? entity.avatar })
        }
    }
}

extension Conversation {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи или в связанной записи аватара нет обязательных полей.
    init?(entity: ConversationEntity) {
        guard let rawType = entity.type,
              let memberIdsData = entity.memberIds,
              let memberIds = try? JSONDecoder().decode([Int].self, from: memberIdsData) else { return nil }
        var avatar: RemoteFile?
        if let avatarEntity = entity.avatar {
            guard let file = RemoteFile(entity: avatarEntity) else { return nil }
            avatar = file
        }
        var lastMessage: LastMessage?
        if let lastMessageId = entity.lastMessageId {
            guard let message = LastMessage(id: lastMessageId, entity: entity) else { return nil }
            lastMessage = message
        }
        self.init(
            conversationId: Int(entity.conversationId),
            type: ConversationType(rawValue: rawType) ?? .unknown,
            memberIds: memberIds,
            name: entity.name,
            avatar: avatar,
            opponentUserId: entity.opponentUserId?.intValue,
            lastMessage: lastMessage,
            positionUpdatedAt: ServerTime(milliseconds: entity.positionUpdatedAt),
            updatedInfoAt: ServerTime(milliseconds: entity.updatedInfoAt)
        )
    }
}

private extension LastMessage {
    /// Собирает последнее сообщение из полей записи переписки.
    /// - Parameters:
    ///   - id: `lastMessageId` записи.
    ///   - entity: запись CoreData.
    /// - Returns: `nil`, если в записи нет обязательных полей последнего сообщения.
    init?(id: NSNumber, entity: ConversationEntity) {
        guard let rawType = entity.lastMessageType, let updatedAt = entity.lastMessageUpdatedAt else { return nil }
        self.init(
            messageId: id.intValue,
            type: MessageType(rawValue: rawType) ?? .unknown,
            text: entity.lastMessageText,
            updatedAt: ServerTime(milliseconds: updatedAt.int64Value)
        )
    }
}
