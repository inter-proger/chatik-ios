//
//  ProfileStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана профиля (таблица `Profile.strings`).
@MainActor
enum ProfileStrings {
    private static let table = "Profile"

    static var title: String { localized("profile.title") }
    static var name: String { localized("profile.name") }
    static var login: String { localized("profile.login") }
    static var userId: String { localized("profile.user_id") }

    /// Возвращает локализованную строку по ключу из таблицы `Profile`.
    /// - Parameter key: ключ в `Profile.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
