//
//  UserEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о пользователе; сырая структура — `User`.
@objc(UserEntity)
final class UserEntity: NSManagedObject, StorageEntity {
    @NSManaged var userId: Int64
    @NSManaged var login: String?
    @NSManaged var name: String?
    @NSManaged var avatar: FileEntity?
    /// Когда данные пользователя получены с сервера — по этой метке кэш решает, устарели ли они.
    @NSManaged var cachedAt: Date?

    static let idKey = "userId"

    var storageId: Int { Int(userId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameters:
    ///   - user: источник данных.
    ///   - avatar: уже сохранённая в том же контексте запись аватара; `nil` — аватара нет.
    ///   - cachedAt: когда данные получены с сервера.
    func update(from user: User, avatar: FileEntity?, cachedAt: Date) {
        userId = Int64(user.userId)
        login = user.login
        name = user.name
        self.avatar = avatar
        self.cachedAt = cachedAt
    }

    /// Сохраняет пользователей вместе с их аватарами в контексте (upsert по `userId`), не вызывая `save()`.
    /// - Parameters:
    ///   - users: сырые структуры пользователей.
    ///   - cachedAt: когда данные получены с сервера.
    ///   - context: фоновый контекст записи.
    /// - Returns: словарь `userId → Entity`.
    static func upsert(_ users: [User], cachedAt: Date, in context: NSManagedObjectContext) throws -> [Int: UserEntity] {
        let avatarsById = try FileEntity.upsert(users.compactMap(\.avatar), in: context)
        return try upsert(users, id: \.userId, in: context) { entity, user in
            entity.update(from: user, avatar: user.avatar.flatMap { avatarsById[$0.fileId] }, cachedAt: cachedAt)
        }
    }
}

extension User {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи или в связанной записи аватара нет обязательных полей.
    init?(entity: UserEntity) {
        guard let login = entity.login, let name = entity.name else { return nil }
        var avatar: RemoteFile?
        if let avatarEntity = entity.avatar {
            guard let file = RemoteFile(entity: avatarEntity) else { return nil }
            avatar = file
        }
        self.init(userId: Int(entity.userId), login: login, name: name, avatar: avatar)
    }
}
