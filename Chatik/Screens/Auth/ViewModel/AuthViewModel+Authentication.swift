//
//  AuthViewModel+Authentication.swift
//  Chatik
//

import Foundation

/// Авторизация: запрос регистрации / входа, открытие сессии и обработка её истечения.
extension AuthViewModel {
    /// Уведомления сейчас показываются — активна хотя бы одна сцена приложения. Отслеживается Observation.
    var canShowNotifications: Bool { notifications.isActive }

    /// Если сессию завершил сервер, объясняет пользователю, почему он разлогинен. Вызывается при появлении экрана
    /// и при каждом включении уведомлений (возврат в активное приложение): истечение отмечается просмотренным,
    /// только когда сообщение действительно показано, — сессия, истёкшая в фоне, объясняется при возврате.
    func showExpirationIfNeeded() {
        guard sessionService.isExpired else { return }
        guard notifications.showError(CommonStrings.errorUnauthorized) else { return }
        sessionService.acknowledgeExpiration()
    }

    /// Обработчик кнопки «Регистрация» / «Вход»: запускает запрос, если он ещё не выполняется.
    func didTapPrimaryButton() {
        guard !isLoading else { return }
        Task { await performAuthentication() }
    }

    /// Выполняет регистрацию или вход в зависимости от режима.
    /// При успехе открывает сессию (приложение переключится на список чатов) и начинает работу с сервером
    /// (`SessionWorkStarting`): отправка сообщений, прерванных прошлой сессией, и `/global/start` с токеном WebSocket
    /// уже для этого пользователя; при ошибке показывает всплывающее сообщение.
    func performAuthentication() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await authenticate()
            await sessionService.start(user: user)
            sessionWork.startSessionWork()
        } catch {
            notifications.showError(ErrorMessages.message(for: error))
        }
    }

    /// Вызывает метод сервиса авторизации, соответствующий текущему режиму.
    /// Логин и имя отправляются без краевых пробелов — валидация их допускает, сервер нет; пароль уходит как есть.
    private func authenticate() async throws -> User {
        let login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .signup:
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await authService.signup(login: login, password: password, name: name)
        case .login:
            return try await authService.login(login: login, password: password)
        }
    }
}
