//
//  MessageResponse.swift
//  Chatik
//

import Foundation

/// Ответ методов, возвращающих одно сообщение: `{ "message": { ... } }`.
struct MessageResponse: Decodable, Equatable {
    let message: Message
}
