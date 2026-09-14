//
//  AuthService.swift
//  Chatik
//

import Foundation

protocol AuthServiceProtocol {
    /// Регистрирует нового пользователя и открывает сессию.
    func signup(login: String, password: String, name: String) async throws -> AuthUser
    /// Выполняет вход существующего пользователя и открывает сессию.
    func login(login: String, password: String) async throws -> AuthUser
    /// Завершает текущую сессию на сервере и удаляет cookie сессии локально.
    func logout() async throws
}

final class AuthService: AuthServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Регистрирует пользователя через `POST /auth/signup`.
    /// - Parameters:
    ///   - login: латиница, цифры, `_`.
    ///   - password: минимум 8 символов, заглавная, строчная буква и цифра.
    ///   - name: буквы, цифры, `-`, `_`, пробел.
    func signup(login: String, password: String, name: String) async throws -> AuthUser {
        try await networkService.request(AuthEndpoint.signup(login: login, password: password, name: name))
    }

    /// Выполняет вход через `POST /auth/login`.
    /// - Parameters:
    ///   - login: логин пользователя.
    ///   - password: пароль пользователя.
    func login(login: String, password: String) async throws -> AuthUser {
        try await networkService.request(AuthEndpoint.login(login: login, password: password))
    }

    /// Завершает сессию через `POST /auth/logout` и очищает cookie сессии.
    /// Если сервер ответил 2003 (сессии уже нет), cookie тоже очищается, а ошибка пробрасывается —
    /// глобальный обработчик 2003 этот запрос не трогает (`AuthEndpoint.terminatesSession`), решение за вызывающим.
    /// При транспортных ошибках cookie сохраняется — сессия на сервере ещё жива.
    func logout() async throws {
        do {
            let _: EmptyResponse = try await networkService.request(AuthEndpoint.logout)
            networkService.clearSessionCookies()
        } catch NetworkError.api(let code) where code == NetworkError.Code.unauthorized {
            networkService.clearSessionCookies()
            throw NetworkError.api(code: code)
        }
    }
}
