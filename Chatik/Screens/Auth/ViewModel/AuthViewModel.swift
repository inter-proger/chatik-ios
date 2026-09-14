//
//  AuthViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана регистрации / входа. Сетевая логика будет добавлена отдельно.
///
/// Здесь — хранимое состояние, зависимости и действия, которые его меняют.
/// Производные данные вынесены в extensions: `AuthViewModel+Validation`, `AuthViewModel+Texts`.
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

    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol
    private let authService: AuthServiceProtocol
    private let router: AuthRouter

    init(
        mode: AuthMode = .signup,
        authService: AuthServiceProtocol,
        signupValidator: SignupValidatorProtocol,
        loginValidator: LoginValidatorProtocol,
        router: AuthRouter
    ) {
        self.mode = mode
        self.authService = authService
        self.signupValidator = signupValidator
        self.loginValidator = loginValidator
        self.router = router
    }

    var isSignup: Bool { mode == .signup }

    // MARK: - Действия

    /// Переключает экран между режимами регистрации и входа.
    func switchMode() {
        mode = mode.toggled
    }

    /// Переключает отображение пароля между секьюрным и открытым текстом.
    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }

    /// Обработчик кнопки «Регистрация» / «Вход». Логика будет добавлена отдельно.
    func didTapPrimaryButton() {
        // TODO: вызов authService.signup / authService.login и переход через router.
    }
}
