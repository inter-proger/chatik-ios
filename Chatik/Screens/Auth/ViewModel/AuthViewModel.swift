//
//  AuthViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана регистрации / входа.
///
/// Здесь — хранимое состояние, зависимости и действия над формой.
/// Остальное вынесено в extensions: `AuthViewModel+Authentication` (запрос регистрации / входа, сессия),
/// `AuthViewModel+Validation`, `AuthViewModel+Texts`.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var mode: AuthMode

    var name = ""
    var login = ""
    var password = ""
    var isPasswordVisible = false
    /// Поле, которое сейчас редактирует пользователь. Синхронизируется из View.
    var focusedField: AuthField?
    /// `true`, пока выполняется запрос регистрации / входа. Меняется только в `AuthViewModel+Authentication`.
    var isLoading = false

    let authService: AuthServiceProtocol
    let sessionService: SessionServiceProtocol
    /// Начало работы с сервером после входа; нужно `AuthViewModel+Authentication`, поэтому не `private`.
    let sessionWork: SessionWorkStarting
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol
    /// Показ ошибок; нужен `AuthViewModel+Authentication`, поэтому не `private`.
    let notifications: InAppNotificationServiceProtocol
    private let localizationService: LocalizationServiceProtocol
    private let router: AuthRouter

    init(
        mode: AuthMode = .signup,
        authService: AuthServiceProtocol,
        sessionService: SessionServiceProtocol,
        sessionWork: SessionWorkStarting,
        localizationService: LocalizationServiceProtocol,
        signupValidator: SignupValidatorProtocol,
        loginValidator: LoginValidatorProtocol,
        notifications: InAppNotificationServiceProtocol,
        router: AuthRouter
    ) {
        self.mode = mode
        self.authService = authService
        self.sessionService = sessionService
        self.sessionWork = sessionWork
        self.localizationService = localizationService
        self.signupValidator = signupValidator
        self.loginValidator = loginValidator
        self.notifications = notifications
        self.router = router
    }

    var isSignup: Bool { mode == .signup }

    /// Текущий язык интерфейса — для отметки выбранного пункта в меню языков.
    var language: AppLanguage { localizationService.language }

    // MARK: - Действия

    /// Переключает экран между режимами регистрации и входа.
    func switchMode() {
        mode = mode.toggled
    }

    /// Переключает отображение пароля между секьюрным и открытым текстом.
    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }

    /// Применяет выбранный в меню язык интерфейса и запоминает его.
    /// - Parameter language: выбранный язык.
    func selectLanguage(_ language: AppLanguage) {
        Task { await localizationService.setLanguage(language) }
    }
}
