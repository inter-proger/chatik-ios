//
//  GroupInfoEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о составе группы (`GroupInfo`). Состав всегда заменяется целиком, поэтому участники хранятся одним
/// JSON-массивом. Пишет только `GroupInfoService` через `GroupInfoStorageService`.
@objc(GroupInfoEntity)
final class GroupInfoEntity: NSManagedObject {
    @NSManaged var conversationId: Int64
    @NSManaged var version: Int64
    /// `GroupInfo.members` в JSON.
    @NSManaged var members: Data?

    static let entityName = "GroupInfoEntity"
    static let conversationIdKey = "conversationId"

    /// Запрос записи группы.
    /// - Parameter conversationId: группа.
    static func makeFetchRequest(conversationId: Int) -> NSFetchRequest<GroupInfoEntity> {
        let request = NSFetchRequest<GroupInfoEntity>(entityName: entityName)
        request.predicate = NSPredicate(format: "%K == %lld", conversationIdKey, Int64(conversationId))
        return request
    }

    /// Переносит состав в Entity.
    /// - Parameter info: состав группы.
    func update(from info: GroupInfo) {
        conversationId = Int64(info.conversationId)
        version = Int64(info.version)
        members = try? JSONEncoder().encode(info.members)
    }
}

extension GroupInfo {
    /// Собирает состав из записи БД.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если участники не разобрались.
    init?(entity: GroupInfoEntity) {
        guard let data = entity.members, let members = try? JSONDecoder().decode([GroupMember].self, from: data) else { return nil }
        self.init(conversationId: Int(entity.conversationId), version: Int(entity.version), members: members)
    }
}
