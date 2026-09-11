//
//  AuthStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана авторизации (таблица `Auth.strings`).
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

    /// Возвращает локализованную строку по ключу из таблицы `Auth`.
    /// - Parameter key: ключ в `Auth.strings`.
    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table)
    }
}
