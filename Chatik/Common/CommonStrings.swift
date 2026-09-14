//
//  CommonStrings.swift
//  Chatik
//

import Foundation

/// Локализованные общие строки (таблица `Common.strings`).
enum CommonStrings {
    private static let table = "Common"

    static var errorTitle: String { localized("common.error.title") }
    static var ok: String { localized("common.ok") }

    static var errorUnknown: String { localized("common.error.unknown") }
    static var errorNoConnection: String { localized("common.error.no_connection") }

    static var errorInvalidLogin: String { localized("common.error.api.invalid_login") }
    static var errorInvalidPassword: String { localized("common.error.api.invalid_password") }
    static var errorInvalidName: String { localized("common.error.api.invalid_name") }
    static var errorLoginAlreadyTaken: String { localized("common.error.api.login_already_taken") }
    static var errorWrongCredentials: String { localized("common.error.api.wrong_credentials") }
    static var errorUnauthorized: String { localized("common.error.api.unauthorized") }

    /// Возвращает локализованную строку по ключу из таблицы `Common`.
    /// - Parameter key: ключ в `Common.strings`.
    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table)
    }
}
