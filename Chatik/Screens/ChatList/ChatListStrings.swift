//
//  ChatListStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана списка чатов (таблица `ChatList.strings`).
@MainActor
enum ChatListStrings {
    private static let table = "ChatList"

    static var title: String { localized("chat_list.title") }
    static var updating: String { localized("chat_list.updating") }
    static var profile: String { localized("chat_list.profile") }
    static var empty: String { localized("chat_list.empty") }
    static var rowUntitled: String { localized("chat_list.row.untitled") }
    static var rowLoading: String { localized("chat_list.row.loading") }
    static var rowDeletedUser: String { localized("chat_list.row.deleted_user") }
    static var rowMessage: String { localized("chat_list.row.message") }
    static var rowNoMessages: String { localized("chat_list.row.no_messages") }
    static var rowDraftPrefix: String { localized("chat_list.row.draft_prefix") }
    static var rowFailedPrefix: String { localized("chat_list.row.failed_prefix") }
    static var rowEditing: String { localized("chat_list.row.editing") }
    static var create: String { localized("chat_list.create") }
    static var createSingle: String { localized("chat_list.create.single") }

    /// Возвращает локализованную строку по ключу из таблицы `ChatList`.
    /// - Parameter key: ключ в `ChatList.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
