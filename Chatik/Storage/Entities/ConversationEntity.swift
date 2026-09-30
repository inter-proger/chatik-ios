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
    @NSManaged var opponentUser: UserEntity?

    static let idKey = "conversationId"

    var storageId: Int { Int(conversationId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameters:
    ///   - conversation: источник данных.
    ///   - avatar: уже сохранённая в том же контексте запись аватара группы; `nil` — аватара нет.
    ///   - opponentUser: уже сохранённая в том же контексте запись собеседника; `nil` — собеседника нет.
    func update(from conversation: Conversation, avatar: FileEntity?, opponentUser: UserEntity?) {
        conversationId = Int64(conversation.conversationId)
        type = conversation.type.rawValue
        memberIds = try? JSONEncoder().encode(conversation.memberIds)
        name = conversation.name
        self.avatar = avatar
        self.opponentUser = opponentUser
    }

    /// Сохраняет переписки вместе с собеседниками и аватарами в контексте (upsert по `conversationId`),
    /// не вызывая `save()`.
    /// - Parameters:
    ///   - conversations: сырые структуры переписок.
    ///   - context: фоновый контекст записи.
    static func upsert(_ conversations: [Conversation], in context: NSManagedObjectContext) throws {
        let avatarsById = try FileEntity.upsert(conversations.compactMap(\.avatar), in: context)
        let usersById = try UserEntity.upsert(conversations.compactMap(\.opponentUser), in: context)
        _ = try upsert(conversations, id: \.conversationId, in: context) { entity, conversation in
            entity.update(
                from: conversation,
                avatar: conversation.avatar.flatMap { avatarsById[$0.fileId] },
                opponentUser: conversation.opponentUser.flatMap { usersById[$0.userId] }
            )
        }
    }
}

extension Conversation {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи или в связанных записях (аватар, собеседник) нет обязательных полей.
    init?(entity: ConversationEntity) {
        guard let rawType = entity.type,
              let memberIdsData = entity.memberIds,
              let memberIds = try? JSONDecoder().decode([Int].self, from: memberIdsData) else { return nil }
        var avatar: RemoteFile?
        if let avatarEntity = entity.avatar {
            guard let file = RemoteFile(entity: avatarEntity) else { return nil }
            avatar = file
        }
        var opponentUser: User?
        if let opponentEntity = entity.opponentUser {
            guard let user = User(entity: opponentEntity) else { return nil }
            opponentUser = user
        }
        self.init(
            conversationId: Int(entity.conversationId),
            type: ConversationType(rawValue: rawType) ?? .unknown,
            memberIds: memberIds,
            name: entity.name,
            avatar: avatar,
            opponentUser: opponentUser
        )
    }
}
