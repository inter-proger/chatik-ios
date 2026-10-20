//
//  AuthServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса авторизации: возвращает заданный результат, запоминает подписчиков и вызовы выхода
/// и позволяет заглянуть в состояние во время запроса. Выход наблюдателей не оповещает — это проверяется
/// в тестах `AuthService`.
@MainActor
final class AuthServiceMock: AuthServiceProtocol {
    var stubbedUser: Result<User, Error> = .failure(NetworkError.missingResponse)
    private(set) var logoutCallCount = 0
    private(set) var expireSessionCallCount = 0
    /// Вызовы регистрации, входа и выхода по порядку: `"signup"`, `"login(<логин>/<пароль>)"`, `"logout"`.
    private(set) var calls: [String] = []
    /// Подписанные наблюдатели (сильные ссылки — чтобы тест мог проверить подписку).
    private(set) var observers: [AuthServiceObserver] = []
    /// Вызывается внутри каждого метода и ожидается до возврата результата — пока ViewModel гарантированно
    /// в состоянии загрузки. Из хука можно читать состояние ViewModel и вызывать её методы.
    var onRequest: (@MainActor () async -> Void)?

    /// Возвращает `stubbedUser` после хука `onRequest`.
    func signup(login: String, password: String, name: String) async throws -> User {
        calls.append("signup")
        await onRequest?()
        return try stubbedUser.get()
    }

    /// Возвращает `stubbedUser` после хука `onRequest`.
    func login(login: String, password: String) async throws -> User {
        calls.append("login(\(login)/\(password))")
        await onRequest?()
        return try stubbedUser.get()
    }

    /// Считает вызов и ждёт хук `onRequest`; наблюдателей не оповещает.
    func logout() async {
        logoutCallCount += 1
        calls.append("logout")
        await onRequest?()
    }

    /// Считает вызов; наблюдателей не оповещает.
    func expireSession() {
        expireSessionCallCount += 1
    }

    /// Запоминает наблюдателя сильной ссылкой — без защиты от повторов.
    /// - Parameter observer: подписываемый наблюдатель.
    func addObserver(_ observer: AuthServiceObserver) {
        observers.append(observer)
    }

    /// Убирает наблюдателя из списка подписанных.
    /// - Parameter observer: отписываемый наблюдатель.
    func removeObserver(_ observer: AuthServiceObserver) {
        observers.removeAll { $0 === observer }
    }
}
