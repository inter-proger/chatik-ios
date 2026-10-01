//
//  ValidationErrors.swift
//  Chatik
//

import Foundation

/// Ошибка валидации имени при регистрации.
enum NameValidationError: Equatable {
    case empty
    case invalidCharacters
    case tooLong(maxLength: Int)
}

/// Ошибка валидации логина при регистрации.
enum LoginValidationError: Equatable {
    case empty
    case invalidCharacters
    case tooLong(maxLength: Int)
}

/// Ошибка валидации текста сообщения перед отправкой или редактированием.
enum MessageTextValidationError: Equatable {
    case empty
    case tooLong(maxLength: Int)
}

/// Ошибка валидации пароля при регистрации. Возвращается первая по порядку нарушенная проверка.
enum PasswordValidationError: Equatable {
    case tooShort
    case missingUppercase
    case missingLowercase
    case missingDigit
}
