//
//  MessageBlock.swift
//  Chatik
//

import Foundation

/// Объект `MessageBlock` из API — блок сообщений целиком, элемент ответа `/messages/getBlockBatch`.
struct MessageBlock: Decodable, Equatable, Sendable {
    let blockId: Int
    let conversationId: Int
    /// Все сообщения блока, сначала самые новые. Пустой массив — все сообщения блока удалены.
    let messages: [Message]
    /// Время последнего изменения или удаления сообщений блока; `nil` — не менялись. Новые сообщения его не меняют.
    let updatedAt: ServerTime?
}
