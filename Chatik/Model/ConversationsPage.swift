//
//  ConversationsPage.swift
//  Chatik
//

import Foundation

/// Страница списка переписок — ответ `/conversations/getList`.
struct ConversationsPage: Equatable {
    /// Переписки в порядке выдачи: без фильтра и с `positionUpdatedAfter` — по убыванию позиции,
    /// с `changedAfter` — по возрастанию `changeVersion`.
    let conversations: [Conversation]
    /// Метки: переписки, в которых пользователь перестал состоять после `changedAfter`, по возрастанию
    /// `changeVersion`. Без `changedAfter` — пусто.
    let removedConversations: [RemovedConversation]
    /// Есть ли переписки после этой страницы (в пределах фильтра).
    let hasNext: Bool
    /// Непрочитанные по всем перепискам на версии `changeVersion`.
    let totalUnreadCount: Int
    /// Версия пользователя, на которой снят ответ.
    let changeVersion: Int

    init(
        conversations: [Conversation],
        removedConversations: [RemovedConversation] = [],
        hasNext: Bool,
        totalUnreadCount: Int,
        changeVersion: Int
    ) {
        self.conversations = conversations
        self.removedConversations = removedConversations
        self.hasNext = hasNext
        self.totalUnreadCount = totalUnreadCount
        self.changeVersion = changeVersion
    }

    /// Наибольшая версия страницы среди переписок и меток — курсор следующей страницы `changedAfter`.
    var maxItemChangeVersion: Int? {
        let versions = conversations.map(\.readState.changeVersion) + removedConversations.map(\.changeVersion)
        return versions.max()
    }
}

extension ConversationsPage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case conversations, removedConversations, hasNext, totalUnreadCount, changeVersion
    }

    /// Разбирает страницу; `removedConversations` может отсутствовать (не `changedAfter`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            conversations: try container.decode([Conversation].self, forKey: .conversations),
            removedConversations: try container.decodeIfPresent([RemovedConversation].self, forKey: .removedConversations) ?? [],
            hasNext: try container.decode(Bool.self, forKey: .hasNext),
            totalUnreadCount: try container.decode(Int.self, forKey: .totalUnreadCount),
            changeVersion: try container.decode(Int.self, forKey: .changeVersion)
        )
    }
}
