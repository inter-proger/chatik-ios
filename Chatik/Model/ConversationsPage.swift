//
//  ConversationsPage.swift
//  Chatik
//

import Foundation

/// Страница списка переписок — ответ `/conversations/getList`.
struct ConversationsPage: Decodable, Equatable {
    /// Переписки в порядке выдачи: без фильтра и с `positionUpdatedAfter` — по убыванию позиции,
    /// с `changedAfter` — по возрастанию `changeVersion`.
    let conversations: [Conversation]
    /// Есть ли переписки после этой страницы (в пределах фильтра).
    let hasNext: Bool
    /// Непрочитанные по всем перепискам на версии `changeVersion`.
    let totalUnreadCount: Int
    /// Версия пользователя, на которой снят ответ.
    let changeVersion: Int
}
