//
//  SessionService.swift
//  Chatik
//

import Foundation

@MainActor
protocol SessionServiceProtocol: AnyObject {
    /// Залогиненный пользователь. `nil` — сессии нет (или она ещё не восстановлена, см. `isRestored`).
    var currentUser: AuthUser? { get }
    var isLoggedIn: Bool { get }
    /// `true`, когда сохранённая сессия прочитана из хранилища и `currentUser` актуален.
    var isRestored: Bool { get }
    /// `true`, если сессия была завершена сервером (код 2003), и пользователю это ещё не показано.
    var isExpired: Bool { get }

    /// Восстанавливает сессию из хранилища при старте приложения.
    func restore() async
    /// Открывает сессию после успешной регистрации / входа и сохраняет пользователя.
    func start(user: AuthUser) async
    /// Завершает сессию по инициативе пользователя (выход).
    func end() async
    /// Завершает сессию по инициативе сервера (код 2003). Если сессии нет — ничего не делает.
    func expire() async
    /// Сбрасывает признак `isExpired` после того, как пользователю показано сообщение.
    func acknowledgeExpiration()
}

/// Единая точка истины о текущей сессии. Хранит пользователя в памяти и в `UserDefaults`;
/// экраны и корневой роутер наблюдают за `currentUser`.
@MainActor
@Observable
final class SessionService: SessionServiceProtocol {
    private(set) var currentUser: AuthUser?
    private(set) var isRestored = false
    private(set) var isExpired = false

    private let userDefaultsService: UserDefaultsServiceProtocol

    init(userDefaultsService: UserDefaultsServiceProtocol) {
        self.userDefaultsService = userDefaultsService
    }

    var isLoggedIn: Bool { currentUser != nil }

    /// Читает сохранённого пользователя из `UserDefaults`. Повторные вызовы ничего не делают.
    func restore() async {
        guard !isRestored else { return }
        currentUser = await userDefaultsService.currentUser()
        isRestored = true
    }

    /// Сохраняет пользователя и открывает сессию.
    /// - Parameter user: пользователь из ответа `/auth/signup` или `/auth/login`.
    func start(user: AuthUser) async {
        currentUser = user
        isExpired = false
        await userDefaultsService.setCurrentUser(user)
    }

    /// Удаляет пользователя из памяти и `UserDefaults`.
    func end() async {
        currentUser = nil
        await userDefaultsService.setCurrentUser(nil)
    }

    /// Завершает сессию и поднимает флаг `isExpired`, чтобы экран авторизации объяснил причину.
    func expire() async {
        guard isLoggedIn else { return }
        await end()
        isExpired = true
    }

    func acknowledgeExpiration() {
        isExpired = false
    }
}
