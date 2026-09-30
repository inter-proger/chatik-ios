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
    static var profile: String { localized("chat_list.profile") }
    static var logout: String { localized("chat_list.logout") }
    static var empty: String { localized("chat_list.empty") }
    static var rowUntitled: String { localized("chat_list.row.untitled") }
    static var create: String { localized("chat_list.create") }
    static var createSingle: String { localized("chat_list.create.single") }

    /// Возвращает локализованную строку по ключу из таблицы `ChatList`.
    /// - Parameter key: ключ в `ChatList.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
