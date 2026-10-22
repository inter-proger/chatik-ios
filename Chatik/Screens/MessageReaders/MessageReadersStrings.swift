//
//  MessageReadersStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки листа «Кем прочитано» (таблица `MessageReaders.strings`).
@MainActor
enum MessageReadersStrings {
    private static let table = "MessageReaders"

    static var empty: String { localized("message_readers.empty") }
    static var failed: String { localized("message_readers.failed") }
    /// Заголовок листа, пока неизвестно, сколько участников прочитали сообщение.
    static var titleUnknown: String { localized("message_readers.title_unknown") }

    /// Заголовок листа.
    /// - Parameter count: сколько участников прочитали сообщение.
    static func title(count: Int) -> String {
        String(format: localized("message_readers.title"), count)
    }

    /// Возвращает локализованную строку по ключу из таблицы `MessageReaders`.
    /// - Parameter key: ключ в `MessageReaders.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
