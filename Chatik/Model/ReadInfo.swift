//
//  ReadInfo.swift
//  Chatik
//

import Foundation

/// Прочтение переписки для текущего пользователя: указатель, счётчик и версия, на которой они сняты.
/// Сливается правилом 4 `ConversationMerger` — по `changeVersion`.
struct ConversationReadState: Hashable, Sendable {
    /// Непрочитанные сообщения переписки.
    let unreadCount: Int
    /// Последнее прочитанное сообщение: всё с id не больше него прочитано; `0` — ничего не прочитано.
    let lastReadMessageId: Int
    /// Версия пользователя на момент последнего изменения переписки для него.
    let changeVersion: Int
}

/// Объект `ReadInfo` из API — снимок прочтения одной переписки и общего счётчика на одной версии. Приходит в ответах
/// `/conversations/markRead` и `/messages/send`, в событиях `conversations` / `read` и `messages` / `received`.
struct ReadInfo: Decodable, Hashable, Sendable {
    let conversationId: Int
    let lastReadMessageId: Int
    let unreadCount: Int
    /// Непрочитанные по всем перепискам; сливается по своей версии, отдельно от переписки.
    let totalUnreadCount: Int
    /// Версия, на которой сняты поля; в событии — версия этого изменения (курсор синхронизации).
    let changeVersion: Int

    /// Прочтение переписки из снимка.
    var readState: ConversationReadState {
        ConversationReadState(unreadCount: unreadCount, lastReadMessageId: lastReadMessageId, changeVersion: changeVersion)
    }
}

/// Ответ `/conversations/markRead`: `{ "readInfo": { ... } }`.
struct ReadInfoResponse: Decodable, Equatable {
    let readInfo: ReadInfo
}
