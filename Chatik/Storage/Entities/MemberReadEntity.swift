//
//  MemberReadEntity.swift
//  Chatik
//

import CoreData

/// Запись БД об указателе прочтения другого участника переписки (`MemberReadMeta`). Ключ — пара `conversationId`
/// и `userId`; пишет только `MemberReadService` через `MemberReadStorageService`.
@objc(MemberReadEntity)
final class MemberReadEntity: NSManagedObject {
    @NSManaged var conversationId: Int64
    @NSManaged var userId: Int64
    @NSManaged var lastReadMessageId: Int64

    static let entityName = "MemberReadEntity"
    static let conversationIdKey = "conversationId"

    /// Запрос указателей переписок.
    /// - Parameter conversationIds: переписки.
    static func makeFetchRequest(conversationIds: [Int]) -> NSFetchRequest<MemberReadEntity> {
        let request = NSFetchRequest<MemberReadEntity>(entityName: entityName)
        request.predicate = NSPredicate(format: "%K IN %@", conversationIdKey, conversationIds.map { Int64($0) })
        return request
    }
}
