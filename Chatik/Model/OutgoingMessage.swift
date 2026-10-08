//
//  OutgoingMessage.swift
//  Chatik
//

import Foundation

/// Состояние сообщения, которое ещё не подтверждено сервером.
enum OutgoingMessageStatus: String, Equatable {
    /// Запрос отправки выполняется или ещё не начат (например, приложение закрылось во время отправки).
    case sending
    /// Отправка не удалась; пользователь может повторить её или удалить сообщение.
    case failed
}

/// Сообщение текущего пользователя, отправленное с этого устройства, но ещё не подтверждённое сервером.
/// Хранится локально, пока сервер не вернёт созданное сообщение с тем же `clientId`, — так оно переживает
/// перезапуск приложения.
struct OutgoingMessage: Equatable, Identifiable {
    /// Идентификатор, сгенерированный клиентом; уходит в `/messages/send` и возвращается в созданном сообщении.
    let clientId: String
    let conversationId: Int
    /// Текущий пользователь на момент отправки.
    let senderId: Int
    let text: String
    /// Время нажатия «Отправить» — по нему неотправленные сообщения упорядочиваются между собой.
    let createdAt: Date
    var status: OutgoingMessageStatus

    var id: String { clientId }

    /// Ключ сопоставления с серверным сообщением.
    var clientKey: MessageClientKey {
        MessageClientKey(senderId: senderId, clientId: clientId)
    }
}
