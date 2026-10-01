//
//  UserCacheServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок кэша пользователей: отдаёт заданные состояния и запоминает запросы загрузки.
/// `@Observable`, как и настоящий кэш, — чтобы проверять, что экран видит изменения.
@MainActor
@Observable
final class UserCacheServiceMock: UserCacheServiceProtocol {
    /// Состояния пользователей; кого здесь нет — `.pending`.
    var users: [Int: CachedUser] = [:]
    private(set) var loadRequests: [[Int]] = []
    /// Вызывается внутри `loadUsers` — пока вызывающий гарантированно ждёт загрузки.
    var onLoad: (@MainActor () async -> Void)?

    func user(id: Int) -> CachedUser {
        users[id] ?? .pending
    }

    func loadUsers(ids: [Int]) async {
        loadRequests.append(ids)
        await onLoad?()
    }
}
