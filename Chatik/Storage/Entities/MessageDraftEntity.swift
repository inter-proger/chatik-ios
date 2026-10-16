//
//  MessageDraftEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о черновике сообщения. Ключ — пара `userId` и `conversationId`: черновики переживают выход
/// из аккаунта (`LocalStorageCleaner` их не удаляет), и пользователей на устройстве разделяет ключ, а не очистка.
@objc(MessageDraftEntity)
final class MessageDraftEntity: NSManagedObject {
    @NSManaged var userId: Int64
    @NSManaged var conversationId: Int64
    @NSManaged var text: String?
    @NSManaged var updatedAt: Date?

    static let entityName = "MessageDraftEntity"
    static let userIdKey = "userId"
    static let conversationIdKey = "conversationId"
    static let updatedAtKey = "updatedAt"

    /// Запрос черновиков пользователя.
    /// - Parameter userId: пользователь, набравший черновики.
    static func makeFetchRequest(userId: Int) -> NSFetchRequest<MessageDraftEntity> {
        let request = NSFetchRequest<MessageDraftEntity>(entityName: entityName)
        request.predicate = NSPredicate(format: "%K == %lld", userIdKey, Int64(userId))
        return request
    }

    /// Запрос черновиков пользователя в переданных переписках.
    /// - Parameters:
    ///   - userId: пользователь, набравший черновики.
    ///   - conversationIds: переписки.
    static func makeFetchRequest(userId: Int, conversationIds: [Int]) -> NSFetchRequest<MessageDraftEntity> {
        let request = makeFetchRequest(userId: userId)
        request.predicate = NSPredicate(
            format: "%K == %lld AND %K IN %@",
            userIdKey, Int64(userId), conversationIdKey, conversationIds.map { Int64($0) }
        )
        return request
    }
}
