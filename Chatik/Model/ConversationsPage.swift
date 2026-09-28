//
//  ConversationsPage.swift
//  Chatik
//

import Foundation

/// Страница списка переписок — ответ `/conversations/getList`.
struct ConversationsPage: Decodable, Equatable {
    /// Переписки по убыванию `conversationId` — сначала самые новые.
    let conversations: [Conversation]
    /// Есть ли переписки после этой страницы.
    let hasNext: Bool
}
