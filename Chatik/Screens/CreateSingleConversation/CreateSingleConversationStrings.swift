//
//  CreateSingleConversationStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки экрана создания личного диалога (таблица `CreateSingleConversation.strings`).
@MainActor
enum CreateSingleConversationStrings {
    private static let table = "CreateSingleConversation"

    static var title: String { localized("create_single_conversation.title") }
    static var create: String { localized("create_single_conversation.create") }
    static var cancel: String { localized("create_single_conversation.cancel") }
    static var searchPrompt: String { localized("create_single_conversation.search_prompt") }
    static var emptyTitle: String { localized("create_single_conversation.empty.title") }
    static var emptySearchTitle: String { localized("create_single_conversation.empty_search.title") }

    /// Возвращает локализованную строку по ключу из таблицы `CreateSingleConversation`.
    /// - Parameter key: ключ в `CreateSingleConversation.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
