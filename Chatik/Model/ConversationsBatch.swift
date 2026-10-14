//
//  ConversationsBatch.swift
//  Chatik
//

import Foundation

/// Переписки по списку id — ответ `/conversations/getBatch`.
struct ConversationsBatch: Decodable, Equatable {
    /// Найденные переписки в порядке запроса (не в порядке списка чатов).
    let conversations: [Conversation]
    /// Id несуществующих переписок и тех, в которых пользователь не состоит.
    let notFoundIds: [Int]
}
