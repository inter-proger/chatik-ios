//
//  UserStorageService.swift
//  Chatik
//

import CoreData

protocol UserStorageServiceProtocol {
    /// Сохраняет пользователя вместе с аватаром (upsert по `userId`).
    func save(user: User) async throws
    /// Сохраняет список пользователей вместе с аватарами одним фоновым контекстом (upsert по `userId`).
    func save(users: [User]) async throws
    /// Возвращает всех сохранённых пользователей.
    func fetchAll() async throws -> [User]
    /// Ищет пользователя по идентификатору.
    func find(byId id: Int) async throws -> User?
    /// Удаляет пользователя по идентификатору, если он найден.
    func delete(byId id: Int) async throws
}

/// Хранилище пользователей в CoreData. Все операции выполняются в фоновых контекстах.
final class UserStorageService: UserStorageServiceProtocol {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    /// Сохраняет одного пользователя: обновляет существующую запись с тем же `userId` или создаёт новую.
    /// - Parameter user: сырая структура пользователя.
    func save(user: User) async throws {
        try await save(users: [user])
    }

    /// Сохраняет список пользователей и их аватары одним фоновым контекстом (upsert по `userId`).
    /// - Parameter users: сырые структуры; повторы `userId` внутри списка схлопываются в одну запись.
    func save(users: [User]) async throws {
        guard !users.isEmpty else { return }
        try await container.performWrite { context in
            _ = try UserEntity.upsert(users, in: context)
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

    /// Удаляет пользователя по идентификатору; ссылки на него в переписках обнуляются.
    /// - Parameter id: идентификатор удаляемого пользователя.
    func delete(byId id: Int) async throws {
        try await container.performWrite { context in
            guard let entity = try context.fetch(UserEntity.makeFetchRequest(id: id)).first else { return }
            context.delete(entity)
            try context.save()
        }
    }
}
