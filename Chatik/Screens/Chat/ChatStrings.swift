//
//  ChatStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана переписки (таблица `Chat.strings`).
@MainActor
enum ChatStrings {
    private static let table = "Chat"

    static var empty: String { localized("chat.empty") }
    static var inputPlaceholder: String { localized("chat.input.placeholder") }
    static var send: String { localized("chat.send") }
    static var messageEdited: String { localized("chat.message.edited") }
    static var messageUnsupported: String { localized("chat.message.unsupported") }
    static var titleUntitled: String { localized("chat.title.untitled") }
    static var userLoading: String { localized("chat.user.loading") }
    static var userDeleted: String { localized("chat.user.deleted") }

    /// Подсказка о превышении длины сообщения.
    /// - Parameter maxLength: лимит длины на стороне сервера.
    static func inputTooLong(maxLength: Int) -> String {
        String(format: localized("chat.input.too_long"), maxLength)
    }

    /// Возвращает локализованную строку по ключу из таблицы `Chat`.
    /// - Parameter key: ключ в `Chat.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
