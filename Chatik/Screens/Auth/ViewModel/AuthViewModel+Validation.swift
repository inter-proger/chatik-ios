//
//  AuthViewModel+Validation.swift
//  Chatik
//

import Foundation

/// Валидация формы: активность кнопки и состояние подсказок / ошибок у полей.
extension AuthViewModel {
    /// Кнопка «Регистрация» активна при полностью валидной форме, «Вход» — при непустых логине и пароле.
    var isPrimaryButtonEnabled: Bool {
        switch mode {
        case .signup: return signupValidator.isFormValid(name: name, login: login, password: password)
        case .login: return loginValidator.isFormValid(login: login, password: password)
        }
    }

    var nameFieldState: AuthFieldState {
        getFieldState(.name, value: name, hint: AuthStrings.hintName, error: signupValidator.validateName(name)?.message)
    }

    var loginFieldState: AuthFieldState {
        getFieldState(.login, value: login, hint: AuthStrings.hintLogin, error: signupValidator.validateLogin(login)?.message)
    }

    var passwordFieldState: AuthFieldState {
        getFieldState(.password, value: password, hint: AuthStrings.hintPassword, error: signupValidator.validatePassword(password)?.message)
    }

    /// Собирает состояние поля для режима регистрации. В режиме входа подсказки и ошибки не показываются.
    /// В фокусе — подсказка о требованиях; без фокуса при непустом невалидном вводе — ошибка с подсветкой.
    /// - Parameters:
    ///   - field: поле формы.
    ///   - value: текущее содержимое поля.
    ///   - hint: текст требований к полю.
    ///   - error: текст ошибки валидации, если поле невалидно.
    private func getFieldState(_ field: AuthField, value: String, hint: String, error: String?) -> AuthFieldState {
        guard isSignup else { return .empty }
        if focusedField == field { return AuthFieldState(message: hint) }
        guard let error, !value.isEmpty else { return .empty }
        return AuthFieldState(message: error, isError: true)
    }
}
