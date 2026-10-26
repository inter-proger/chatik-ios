//
//  GroupMembersStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана участников группы (таблица `GroupMembers.strings`).
@MainActor
enum GroupMembersStrings {
    private static let table = "GroupMembers"

    static var title: String { localized("group_members.title") }
    static var ownerSection: String { localized("group_members.section.owner") }
    static var membersSection: String { localized("group_members.section.members") }
    static var you: String { localized("group_members.you") }
    static var loadFailed: String { localized("group_members.load_failed") }
    static var retry: String { localized("group_members.retry") }
    static var transferOwnership: String { localized("group_members.transfer") }
    static var transferTitle: String { localized("group_members.transfer.title") }
    static var transferConfirm: String { localized("group_members.transfer.confirm") }
    static var transferCancel: String { localized("group_members.transfer.cancel") }
    static var ownershipTransferred: String { localized("group_members.transferred") }

    /// Текст подтверждения передачи прав.
    /// - Parameter name: имя будущего создателя.
    static func transferMessage(name: String) -> String {
        String(format: localized("group_members.transfer.message"), name)
    }

    /// Возвращает локализованную строку по ключу из таблицы `GroupMembers`.
    /// - Parameter key: ключ в `GroupMembers.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
