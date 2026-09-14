//
//  AuthServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса авторизации: возвращает заданный результат и позволяет заглянуть в состояние во время запроса.
final class AuthServiceMock: AuthServiceProtocol {
    var stubbedUser: Result<AuthUser, Error> = .failure(NetworkError.missingResponse)
    var stubbedLogout: Result<Void, Error> = .success(())
    /// Вызывается внутри каждого метода — до возврата результата, пока ViewModel в состоянии загрузки.
    var onRequest: (() -> Void)?

    func signup(login: String, password: String, name: String) async throws -> AuthUser {
        onRequest?()
        return try stubbedUser.get()
    }

    func login(login: String, password: String) async throws -> AuthUser {
        onRequest?()
        return try stubbedUser.get()
    }

    func logout() async throws {
        onRequest?()
        try stubbedLogout.get()
    }
}
