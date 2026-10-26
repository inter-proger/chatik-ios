//
//  GroupOptionsStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана опций группы (таблица `GroupOptions.strings`).
@MainActor
enum GroupOptionsStrings {
    private static let table = "GroupOptions"

    static var title: String { localized("group_options.title") }
    static var untitled: String { localized("group_options.untitled") }
    static var members: String { localized("group_options.members") }
    static var addMembers: String { localized("group_options.add_members") }
    static var leave: String { localized("group_options.leave") }
    static var leaveConfirmTitle: String { localized("group_options.leave.confirm_title") }
    static var leaveConfirmButton: String { localized("group_options.leave.confirm_button") }
    static var leaveCancel: String { localized("group_options.leave.cancel") }
    static var leaveMessage: String { localized("group_options.leave.message") }
    static var leaveMessageOwner: String { localized("group_options.leave.message_owner") }
    static var leaveMessageLastMember: String { localized("group_options.leave.message_last_member") }
    static var left: String { localized("group_options.left") }

    /// Возвращает локализованную строку по ключу из таблицы `GroupOptions`.
    /// - Parameter key: ключ в `GroupOptions.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
