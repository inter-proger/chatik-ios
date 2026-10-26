//
//  CreateGroupStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана создания группы (таблица `CreateGroup.strings`).
@MainActor
enum CreateGroupStrings {
    private static let table = "CreateGroup"

    static var title: String { localized("create_group.title") }
    static var create: String { localized("create_group.create") }
    static var cancel: String { localized("create_group.cancel") }
    static var namePlaceholder: String { localized("create_group.name_placeholder") }
    static var descriptionPlaceholder: String { localized("create_group.description_placeholder") }
    static var avatarTitle: String { localized("create_group.avatar.title") }
    static var avatarChooseFromGallery: String { localized("create_group.avatar.choose_from_gallery") }
    static var avatarTakePhoto: String { localized("create_group.avatar.take_photo") }
    static var avatarRemove: String { localized("create_group.avatar.remove") }
    static var avatarAccessibilityLabel: String { localized("create_group.avatar.accessibility_label") }
    static var avatarLoadFailed: String { localized("create_group.avatar.load_failed") }
    static var invalidName: String { localized("create_group.error.invalid_name") }

    /// Подсказка под полем, длина которого превысила лимит.
    /// - Parameter maxLength: лимит в символах.
    static func tooLong(maxLength: Int) -> String {
        Localized.plural("create_group.too_long", table: table, count: maxLength)
    }

    /// Возвращает локализованную строку по ключу из таблицы `CreateGroup`.
    /// - Parameter key: ключ в `CreateGroup.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
