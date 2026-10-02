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
    /// Время изменения полей переписки. Записям, сохранённым до появления поля, миграция проставляет 1970 год:
    /// любая версия с сервера их новее.
    @NSManaged var updatedAt: Date?

    static let idKey = "conversationId"

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
        updatedAt = conversation.updatedAt
    }

    /// `true`, если в записи версия переписки новее `conversation`: такую запись перезаписывать нельзя —
    /// событие WebSocket могло прийти раньше ответа REST с более старыми данными.
    /// - Parameter conversation: версия, которую собираются сохранить.
    func isNewer(than conversation: Conversation) -> Bool {
        guard let updatedAt else { return false }
        return updatedAt > conversation.updatedAt
    }

    /// Сохраняет переписки вместе с аватарами в контексте (upsert по `conversationId`),
    /// не вызывая `save()`. Запись, в которой версия новее сохраняемой, не меняется.
    /// - Parameters:
    ///   - conversations: сырые структуры переписок.
    ///   - context: фоновый контекст записи.
    static func upsert(_ conversations: [Conversation], in context: NSManagedObjectContext) throws {
        let avatarsById = try FileEntity.upsert(conversations.compactMap(\.avatar), in: context)
        _ = try upsert(conversations, id: \.conversationId, in: context) { entity, conversation in
            guard !entity.isNewer(than: conversation) else { return }
            entity.update(from: conversation, avatar: conversation.avatar.flatMap { avatarsById[$0.fileId] })
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
              let memberIds = try? JSONDecoder().decode([Int].self, from: memberIdsData),
              let updatedAt = entity.updatedAt else { return nil }
        var avatar: RemoteFile?
        if let avatarEntity = entity.avatar {
            guard let file = RemoteFile(entity: avatarEntity) else { return nil }
            avatar = file
        }
        self.init(
            conversationId: Int(entity.conversationId),
            type: ConversationType(rawValue: rawType) ?? .unknown,
            memberIds: memberIds,
            name: entity.name,
            avatar: avatar,
            opponentUserId: entity.opponentUserId?.intValue,
            updatedAt: updatedAt
        )
    }
}
