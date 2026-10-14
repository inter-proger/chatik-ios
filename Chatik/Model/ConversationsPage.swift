//
//  ConversationsPage.swift
//  Chatik
//

import Foundation

/// Страница списка переписок — ответ `/conversations/getList`.
struct ConversationsPage: Decodable, Equatable {
    /// Переписки в порядке выдачи: без фильтра и с `positionUpdatedAfter` — по убыванию позиции,
    /// с `updatedInfoAfter` — по возрастанию `(updatedInfoAt, conversationId)`.
    let conversations: [Conversation]
    /// Есть ли переписки после этой страницы (в пределах фильтра).
    let hasNext: Bool
}
