//
//  ConversationResponse.swift
//  Chatik
//

import Foundation

/// Ответ методов, возвращающих одну переписку: `{ "conversation": { ... } }`.
struct ConversationResponse: Decodable, Equatable {
    let conversation: Conversation
}
