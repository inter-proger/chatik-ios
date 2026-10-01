//
//  UserStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища пользователей в памяти: отдаёт сохранённых и запоминает записи.
/// Состояние изолировано на main actor: мок вызывает actor кэша пользователей (в том числе одновременно),
/// а тесты читают его синхронно. Методы протокола `nonisolated` и переходят на main actor через `await`.
@MainActor
final class UserStorageServiceMock: UserStorageServiceProtocol {
    var storedUsers: [Int: StoredUser] = [:]
    /// Ошибка чтения `findStored(byIds:)`; `nil` — чтение успешно.
    var stubbedFindError: Error?
    private(set) var savedBatches: [(users: [User], cachedAt: Date)] = []
    /// Вызывается внутри `findStored(byIds:)` с номером вызова (с нуля) до возврата результата — пока идёт чтение.
    var onFindStored: (@MainActor (Int) async -> Void)?
    private(set) var findStoredCallCount = 0

    nonisolated func save(user: User) async throws {
        try await save(users: [user])
    }

    nonisolated func save(users: [User]) async throws {
        try await save(users: users, cachedAt: Date())
    }

    nonisolated func save(users: [User], cachedAt: Date) async throws {
        await store(users, cachedAt: cachedAt)
    }

    nonisolated func fetchAll() async throws -> [User] {
        await storedUsers.values.map(\.user)
    }

    nonisolated func find(byId id: Int) async throws -> User? {
        await storedUsers[id]?.user
    }

    nonisolated func findStored(byIds ids: [Int]) async throws -> [StoredUser] {
        try await recordFindStored(ids: ids)
    }

    nonisolated func delete(byId id: Int) async throws {
        await remove(id: id)
    }

    private func store(_ users: [User], cachedAt: Date) {
        savedBatches.append((users, cachedAt))
        users.forEach { storedUsers[$0.userId] = StoredUser(user: $0, cachedAt: cachedAt) }
    }

    private func recordFindStored(ids: [Int]) async throws -> [StoredUser] {
        let result = ids.compactMap { storedUsers[$0] }
        let callIndex = findStoredCallCount
        findStoredCallCount += 1
        await onFindStored?(callIndex)
        if let stubbedFindError { throw stubbedFindError }
        return result
    }

    private func remove(id: Int) {
        storedUsers[id] = nil
    }
}
