//
//  UserStorageService.swift
//  Chatik
//

import CoreData

/// Пользователь из БД вместе с моментом, когда его данные получены с сервера.
struct StoredUser: Equatable {
    let user: User
    /// Когда данные получены с сервера; у записей без метки — `.distantPast`, они считаются устаревшими.
    let cachedAt: Date
}

/// `Sendable`: хранилище вызывается из actor кэша пользователей.
protocol UserStorageServiceProtocol: Sendable {
    /// Сохраняет пользователя вместе с аватаром (upsert по `userId`), отмечая текущее время получения.
    func save(user: User) async throws
    /// Сохраняет список пользователей вместе с аватарами одним фоновым контекстом (upsert по `userId`),
    /// отмечая текущее время получения.
    func save(users: [User]) async throws
    /// Сохраняет список пользователей с указанным временем получения с сервера.
    func save(users: [User], cachedAt: Date) async throws
    /// Возвращает всех сохранённых пользователей.
    func fetchAll() async throws -> [User]
    /// Ищет пользователя по идентификатору.
    func find(byId id: Int) async throws -> User?
    /// Ищет пользователей по списку идентификаторов вместе со временем получения.
    func findStored(byIds ids: [Int]) async throws -> [StoredUser]
    /// Удаляет пользователя по идентификатору, если он найден.
    func delete(byId id: Int) async throws
}

/// Хранилище пользователей в CoreData. Все операции выполняются в фоновых контекстах.
///
/// `@unchecked Sendable`: единственное состояние — `NSPersistentContainer`, который не объявлен `Sendable`,
/// но используется только через `performBackgroundTask`, безопасный для вызова из любого потока;
/// `viewContext` и другие контексты, привязанные к потоку, не используются.
final class UserStorageService: UserStorageServiceProtocol, @unchecked Sendable {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    /// Сохраняет одного пользователя: обновляет существующую запись с тем же `userId` или создаёт новую.
    /// - Parameter user: сырая структура пользователя.
    func save(user: User) async throws {
        try await save(users: [user])
    }

    /// Сохраняет список пользователей и их аватары одним фоновым контекстом (upsert по `userId`),
    /// отмечая временем получения текущий момент.
    /// - Parameter users: сырые структуры; повторы `userId` внутри списка схлопываются в одну запись.
    func save(users: [User]) async throws {
        try await save(users: users, cachedAt: Date())
    }

    /// Сохраняет список пользователей и их аватары одним фоновым контекстом (upsert по `userId`).
    /// - Parameters:
    ///   - users: сырые структуры; повторы `userId` внутри списка схлопываются в одну запись.
    ///   - cachedAt: когда данные получены с сервера.
    func save(users: [User], cachedAt: Date) async throws {
        guard !users.isEmpty else { return }
        try await container.performWrite { context in
            _ = try UserEntity.upsert(users, cachedAt: cachedAt, in: context)
            try context.save()
        }
    }

    /// Возвращает всех сохранённых пользователей; записи с битыми данными пропускаются.
    func fetchAll() async throws -> [User] {
        try await container.performBackgroundTask { context in
            try context.fetch(UserEntity.makeFetchRequest()).compactMap(User.init(entity:))
        }
    }

    /// Ищет пользователя по идентификатору.
    /// - Parameter id: идентификатор искомого пользователя.
    func find(byId id: Int) async throws -> User? {
        try await container.performBackgroundTask { context in
            try context.fetch(UserEntity.makeFetchRequest(id: id)).first.flatMap(User.init(entity:))
        }
    }

    /// Ищет пользователей одним запросом; тех, кого нет в БД (или чья запись битая), в результате нет.
    /// - Parameter ids: идентификаторы искомых пользователей.
    /// - Returns: найденные пользователи со временем получения, в произвольном порядке.
    func findStored(byIds ids: [Int]) async throws -> [StoredUser] {
        try await container.performBackgroundTask { context in
            try UserEntity.fetchById(ids: ids, in: context).values.compactMap { entity in
                User(entity: entity).map { StoredUser(user: $0, cachedAt: entity.cachedAt ?? .distantPast) }
            }
        }
    }

    /// Удаляет пользователя по идентификатору.
    /// - Parameter id: идентификатор удаляемого пользователя.
    func delete(byId id: Int) async throws {
        try await container.performWrite { context in
            guard let entity = try context.fetch(UserEntity.makeFetchRequest(id: id)).first else { return }
            context.delete(entity)
            try context.save()
        }
    }
}
