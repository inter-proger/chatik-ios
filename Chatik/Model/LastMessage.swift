//
//  LastMessage.swift
//  Chatik
//

import Foundation

/// Объект `LastMessage` из API — краткое представление последнего сообщения переписки для списка чатов.
/// Время отправки в него не входит — это `positionUpdatedAt` переписки.
struct LastMessage: Hashable, Sendable, Decodable {
    let messageId: Int
    let type: MessageType
    /// Текст; `nil` для будущих типов без текста.
    let text: String?
    /// Как `Message.updatedAt`; версия текста при слиянии.
    let updatedAt: ServerTime
}

extension LastMessage {
    /// Превью из сообщения — например, из ответа `/messages/send`.
    /// - Parameter message: сообщение, ставшее последним в переписке.
    init(message: Message) {
        self.init(messageId: message.messageId, type: message.type, text: message.text, updatedAt: message.updatedAt)
    }
}
