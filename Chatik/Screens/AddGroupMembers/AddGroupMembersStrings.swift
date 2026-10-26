//
//  AddGroupMembersStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана добавления участников (таблица `AddGroupMembers.strings`).
@MainActor
enum AddGroupMembersStrings {
    private static let table = "AddGroupMembers"

    static var title: String { localized("add_group_members.title") }
    static var add: String { localized("add_group_members.add") }
    static var searchPrompt: String { localized("add_group_members.search_prompt") }
    static var filterAll: String { localized("add_group_members.filter.all") }
    static var filterNotInGroup: String { localized("add_group_members.filter.not_in_group") }
    static var inGroup: String { localized("add_group_members.in_group") }
    static var limitReached: String { localized("add_group_members.limit_reached") }
    static var emptyTitle: String { localized("add_group_members.empty.title") }
    static var emptySearchTitle: String { localized("add_group_members.empty_search.title") }
    static var loadFailed: String { localized("add_group_members.load_failed") }
    static var retry: String { localized("add_group_members.retry") }
    static var allAdded: String { localized("add_group_members.all_added") }
    static var notAddedTitle: String { localized("add_group_members.not_added.title") }
    static var notAddedClose: String { localized("add_group_members.not_added.close") }
    static var reasonUserNotFound: String { localized("add_group_members.reason.user_not_found") }
    static var reasonLimitReached: String { localized("add_group_members.reason.limit_reached") }
    static var reasonAlreadyMember: String { localized("add_group_members.reason.already_member") }

    /// Заголовок при выбранных пользователях: «Добавить: X».
    /// - Parameter count: число выбранных.
    static func titleSelected(count: Int) -> String {
        String(format: localized("add_group_members.title_selected"), count)
    }

    /// Уведомление о не добавленных: «X участников не было добавлено».
    /// - Parameter count: число не добавленных.
    static func notAdded(count: Int) -> String {
        Localized.plural("add_group_members.not_added", table: table, count: count)
    }

    /// Возвращает локализованную строку по ключу из таблицы `AddGroupMembers`.
    /// - Parameter key: ключ в `AddGroupMembers.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
