//
//  SplashStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана загрузки (таблица `Splash.strings`).
enum SplashStrings {
    private static let table = "Splash"

    static var title: String { localized("splash.title") }
    static var subtitle: String { localized("splash.subtitle") }

    /// Возвращает локализованную строку по ключу из таблицы `Splash`.
    /// - Parameter key: ключ в `Splash.strings`.
    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: table)
    }
}
