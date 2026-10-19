//
//  MessageEditResult.swift
//  Chatik
//

import Foundation

/// Ответ `/messages/edit`: сообщение и новое превью переписки, если отредактировано последнее сообщение.
struct MessageEditResult: Decodable, Equatable, Sendable {
    let message: Message
    /// `nil` — отредактировано не последнее сообщение или текст не изменился.
    let lastMessage: LastMessage?
}
