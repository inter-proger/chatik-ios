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

    static var avatarTitle: String { localized("profile.avatar.title") }
    static var avatarChooseFromGallery: String { localized("profile.avatar.choose_from_gallery") }
    static var avatarTakePhoto: String { localized("profile.avatar.take_photo") }
    static var avatarLoadFailed: String { localized("profile.avatar.load_failed") }

    /// Возвращает локализованную строку по ключу из таблицы `Profile`.
    /// - Parameter key: ключ в `Profile.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
