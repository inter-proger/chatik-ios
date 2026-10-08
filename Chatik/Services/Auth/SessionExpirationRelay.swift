//
//  SessionExpirationRelay.swift
//  Chatik
//

import Foundation

/// Передаёт истечение сессии (код 2003) из сетевого слоя в `AuthService`. Нужен, потому что сетевой слой
/// собирается раньше сервиса авторизации, который от него зависит: ссылка на сервис проставляется после сборки.
@MainActor
final class SessionExpirationRelay {
    weak var authService: AuthServiceProtocol?

    /// Сообщает сервису авторизации, что сессия истекла; выход идёт отдельной задачей и здесь не ожидается.
    func expireSession() {
        authService?.expireSession()
    }
}
