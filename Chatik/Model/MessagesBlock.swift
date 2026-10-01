//
//  MessagesBlock.swift
//  Chatik
//

import Foundation

/// Сообщения одного блока — ответ `/messages/getBlock`.
struct MessagesBlock: Decodable, Equatable {
    /// До 20 сообщений блока, сначала самые новые.
    let messages: [Message]
}
