//
//  AuthStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана авторизации (таблица `Auth.strings`).
@MainActor
enum AuthStrings {
    private static let table = "Auth"

    static var titleSignup: String { localized("auth.title.signup") }
    static var titleLogin: String { localized("auth.title.login") }

    static var fieldName: String { localized("auth.field.name") }
    static var fieldLogin: String { localized("auth.field.login") }
    static var fieldPassword: String { localized("auth.field.password") }

    static var passwordShow: String { localized("auth.password.show") }
    static var passwordHide: String { localized("auth.password.hide") }

    static var buttonSignup: String { localized("auth.button.signup") }
    static var buttonLogin: String { localized("auth.button.login") }

    static var agreementFormat: String { localized("auth.agreement") }

    static var switchToLoginFormat: String { localized("auth.switch.to_login") }
    static var switchToSignupFormat: String { localized("auth.switch.to_signup") }

    static var hintName: String { localized("auth.hint.name") }
    static var hintLogin: String { localized("auth.hint.login") }
    static var hintPassword: String { localized("auth.hint.password") }

    static var errorNameEmpty: String { localized("auth.error.name.empty") }
    static var errorNameInvalidCharacters: String { localized("auth.error.name.invalid_characters") }
    static var errorLoginEmpty: String { localized("auth.error.login.empty") }
    static var errorLoginInvalidCharacters: String { localized("auth.error.login.invalid_characters") }

    /// Сообщение о слишком длинном имени.
    /// - Parameter maxLength: максимально допустимая длина имени.
    static func errorNameTooLong(maxLength: Int) -> String {
        String(format: localized("auth.error.name.too_long"), maxLength)
    }

    /// Сообщение о слишком длинном логине.
    /// - Parameter maxLength: максимально допустимая длина логина.
    static func errorLoginTooLong(maxLength: Int) -> String {
        String(format: localized("auth.error.login.too_long"), maxLength)
    }

    static var errorPasswordTooShort: String { localized("auth.error.password.too_short") }
    static var errorPasswordMissingUppercase: String { localized("auth.error.password.missing_uppercase") }
    static var errorPasswordMissingLowercase: String { localized("auth.error.password.missing_lowercase") }
    static var errorPasswordMissingDigit: String { localized("auth.error.password.missing_digit") }

    static var language: String { localized("auth.language") }

    /// Возвращает локализованную строку по ключу из таблицы `Auth`.
    /// - Parameter key: ключ в `Auth.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
