//
//  AuthServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса авторизации: возвращает заданный результат и позволяет заглянуть в состояние во время запроса.
final class AuthServiceMock: AuthServiceProtocol {
    var stubbedUser: Result<User, Error> = .failure(NetworkError.missingResponse)
    var stubbedLogout: Result<Void, Error> = .success(())
    /// Вызывается внутри каждого метода и ожидается до возврата результата — пока ViewModel гарантированно
    /// в состоянии загрузки. `@MainActor`, чтобы из хука можно было читать состояние ViewModel и вызывать её методы.
    var onRequest: (@MainActor () async -> Void)?

    func signup(login: String, password: String, name: String) async throws -> User {
        await onRequest?()
        return try stubbedUser.get()
    }

    func login(login: String, password: String) async throws -> User {
        await onRequest?()
        return try stubbedUser.get()
    }

    func logout() async throws {
        await onRequest?()
        try stubbedLogout.get()
    }
}
