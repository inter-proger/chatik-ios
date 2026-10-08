//
//  AuthService.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol AuthServiceProtocol: AnyObject {
    /// Регистрирует нового пользователя и открывает сессию.
    func signup(login: String, password: String, name: String) async throws -> User
    /// Выполняет вход существующего пользователя и открывает сессию.
    func login(login: String, password: String) async throws -> User
    /// Выходит из аккаунта: завершает сессию на сервере и разлогинивает устройство — даже если запрос не удался.
    /// Наблюдатели узнают о выходе через `AuthServiceObserver`. Если выход уже идёт — ничего не делает.
    func logout() async
    /// Сессия истекла на сервере: разлогинивает устройство без запроса. Не ждёт окончания выхода.
    func expireSession()
    /// Подписывает на выход из аккаунта. Наблюдатель хранится слабо; повторная подписка не дублирует уведомления.
    func addObserver(_ observer: AuthServiceObserver)
    /// Отписывает от выхода из аккаунта.
    func removeObserver(_ observer: AuthServiceObserver)
}

/// Сервис авторизации: регистрация, вход и выход. О выходе — и по кнопке, и по истечению сессии — оповещает
/// наблюдателей (`AuthServiceObserver`): сессия, WebSocket и экраны реагируют на него сами, а экран с кнопкой
/// «Выйти» и сетевой слой о них не знают.
@MainActor
final class AuthService: AuthServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let observers = AuthServiceObservers()

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Регистрирует пользователя через `POST /auth/signup`.
    /// - Parameters:
    ///   - login: латиница, цифры, `_`.
    ///   - password: минимум 8 символов, заглавная, строчная буква и цифра.
    ///   - name: буквы, цифры, `-`, `_`, пробел.
    func signup(login: String, password: String, name: String) async throws -> User {
        try await networkService.request(AuthEndpoint.signup(login: login, password: password, name: name))
    }

    /// Выполняет вход через `POST /auth/login`.
    /// - Parameters:
    ///   - login: логин пользователя.
    ///   - password: пароль пользователя.
    func login(login: String, password: String) async throws -> User {
        try await networkService.request(AuthEndpoint.login(login: login, password: password))
    }

    /// Выходит из аккаунта через `POST /auth/logout`. Устройство разлогинивается при любом ответе сервера:
    /// пользователь нажал «Выйти» и не должен остаться в аккаунте из-за сети. Ошибка запроса только логируется —
    /// сессия на сервере в худшем случае истечёт сама.
    ///
    /// Порядок: наблюдатели останавливают работу с сессией (`authServiceWillLogout`) → запрос → удаление cookie →
    /// наблюдатели узнают о выходе (`authServiceDidLogout`). Если выход уже идёт — ничего не делает.
    func logout() async {
        await observers.performLogout(reason: .userInitiated) {
            await requestLogout()
        }
    }

    /// Сессия истекла на сервере (2003, `null` из `/global/start`): наблюдатели проходят те же фазы, что и при выходе,
    /// но запроса нет — сессии на сервере уже нет. Если выход уже идёт — ничего не делает.
    ///
    /// Выход запускается отдельной задачей, а не ожидается на месте: истечение замечает работа, которую наблюдатели
    /// дожидаются в `authServiceWillLogout` (загрузка списка, цикл WebSocket), — ожидание из неё привело бы
    /// к взаимной блокировке.
    func expireSession() {
        Task {
            await observers.performLogout(reason: .sessionExpired) {
                networkService.clearSessionCookies()
            }
        }
    }

    /// Подписывает наблюдателя на выход; повторная подписка того же объекта ничего не меняет.
    /// - Parameter observer: наблюдатель; хранится слабо.
    func addObserver(_ observer: AuthServiceObserver) {
        observers.add(observer)
    }

    /// Отписывает наблюдателя от выхода.
    /// - Parameter observer: наблюдатель, которого нужно отписать.
    func removeObserver(_ observer: AuthServiceObserver) {
        observers.remove(observer)
    }

    /// Отправляет `POST /auth/logout` и удаляет cookie сессии при любом ответе; ошибка только логируется.
    private func requestLogout() async {
        do {
            let _: EmptyResponse = try await networkService.request(AuthEndpoint.logout)
        } catch {
            Logger.auth.error("Запрос выхода не удался, выход выполнен локально: \(String(describing: error), privacy: .public)")
        }
        networkService.clearSessionCookies()
    }
}

extension Logger {
    /// Лог авторизации.
    static let auth = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Auth")
}
