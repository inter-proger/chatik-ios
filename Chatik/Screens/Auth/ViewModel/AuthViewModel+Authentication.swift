//
//  AuthViewModel+Authentication.swift
//  Chatik
//

import Foundation

/// Авторизация: запрос регистрации / входа, открытие сессии и обработка её истечения.
extension AuthViewModel {
    /// Вызывается при появлении экрана. Если сессию завершил сервер, объясняет пользователю, почему он разлогинен.
    func handleAppear() {
        guard sessionService.isExpired else { return }
        sessionService.acknowledgeExpiration()
        errorMessage = CommonStrings.errorUnauthorized
    }

    /// Обработчик кнопки «Регистрация» / «Вход»: запускает запрос, если он ещё не выполняется.
    func didTapPrimaryButton() {
        guard !isLoading else { return }
        Task { await performAuthentication() }
    }

    /// Выполняет регистрацию или вход в зависимости от режима.
    /// При успехе открывает сессию (приложение переключится на список чатов),
    /// при ошибке показывает всплывающее сообщение.
    func performAuthentication() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await authenticate()
            await sessionService.start(user: user)
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Вызывает метод сервиса авторизации, соответствующий текущему режиму.
    private func authenticate() async throws -> AuthUser {
        switch mode {
        case .signup: return try await authService.signup(login: login, password: password, name: name)
        case .login: return try await authService.login(login: login, password: password)
        }
    }
}
