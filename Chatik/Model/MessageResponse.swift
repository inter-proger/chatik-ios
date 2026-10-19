//
//  MessageResponse.swift
//  Chatik
//

import Foundation

/// Ответ `/messages/send`: `{ "message": { ... } }`.
struct MessageResponse: Decodable, Equatable {
    let message: Message
}
