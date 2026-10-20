//
//  DebugLoginStrings.swift
//  Chatik
//

#if DEBUG
import Foundation

/// Локализованные строки стартового экрана debug-входа (таблица `DebugLogin.strings`).
@MainActor
enum DebugLoginStrings {
    private static let table = "DebugLogin"

    static var title: String { localized("debugLogin.title") }
    static var skip: String { localized("debugLogin.skip") }
    static var errorMissingLogin: String { localized("debugLogin.error.missingLogin") }
    static var errorMissingPassword: String { localized("debugLogin.error.missingPassword") }

    /// Подпись под индикатором входа.
    /// - Parameter login: логин из аргументов запуска.
    static func progress(login: String) -> String {
        String(format: localized("debugLogin.progress"), login)
    }

    /// Текст ошибки разбора аргументов запуска.
    /// - Parameter error: ошибка `DebugLaunchArguments.parse`.
    static func message(for error: DebugLaunchArgumentsError) -> String {
        switch error {
        case .missingLogin: return errorMissingLogin
        case .missingPassword: return errorMissingPassword
        }
    }

    /// Возвращает локализованную строку по ключу из таблицы `DebugLogin`.
    /// - Parameter key: ключ в `DebugLogin.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
#endif
