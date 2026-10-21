//
//  MessageResponse.swift
//  Chatik
//

import Foundation

/// Ответ `/messages/send`: `{ "message": { ... }, "readInfo": { ... } }`.
struct MessageResponse: Decodable, Equatable {
    let message: Message
    /// Прочтение для отправителя: своё сообщение отмечает переписку прочитанной. `nil` — поля нет в ответе.
    let readInfo: ReadInfo?
}
