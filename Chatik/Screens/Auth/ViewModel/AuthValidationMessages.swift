//
//  AuthValidationMessages.swift
//  Chatik
//

import Foundation

/// Сопоставление ошибок валидации с локализованными текстами подсказок экрана авторизации.
@MainActor
extension NameValidationError {
    var message: String {
        switch self {
        case .empty: return AuthStrings.errorNameEmpty
        case .invalidCharacters: return AuthStrings.errorNameInvalidCharacters
        }
    }
}

@MainActor
extension LoginValidationError {
    var message: String {
        switch self {
        case .empty: return AuthStrings.errorLoginEmpty
        case .invalidCharacters: return AuthStrings.errorLoginInvalidCharacters
        }
    }
}

@MainActor
extension PasswordValidationError {
    var message: String {
        switch self {
        case .tooShort: return AuthStrings.errorPasswordTooShort
        case .missingUppercase: return AuthStrings.errorPasswordMissingUppercase
        case .missingLowercase: return AuthStrings.errorPasswordMissingLowercase
        case .missingDigit: return AuthStrings.errorPasswordMissingDigit
        }
    }
}
