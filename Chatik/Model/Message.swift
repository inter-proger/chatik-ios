//
//  Message.swift
//  Chatik
//

import Foundation

/// Тип сообщения. Список будет расширяться: неизвестные значения читаются как `.unknown`,
/// чтобы новый тип с сервера не ломал разбор всего списка.
enum MessageType: String, Decodable, Equatable {
    /// Текстовое сообщение.
    case text
    /// Тип, которого клиент ещё не знает.
    case unknown

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = MessageType(rawValue: rawValue) ?? .unknown
    }
}

/// Объект `Message` из API — одно сообщение переписки.
struct Message: Equatable, Identifiable {
    let messageId: Int
    /// Идентификатор, сгенерированный клиентом-отправителем при отправке; уникален в пределах отправителя.
    /// По нему отправленное с этого устройства сообщение сопоставляется с ответом сервера и событием WebSocket.
    let clientId: String
    let conversationId: Int
    /// Блок, в котором лежит сообщение; блоки одной переписки возрастают от старых к новым.
    let blockId: Int
    /// Пользователь-отправитель.
    let senderId: Int
    let type: MessageType
    /// Текст, 1–4096 символов после обрезки пробелов.
    let text: String
    /// Было ли сообщение отредактировано.
    let isEdited: Bool
    let createdAt: Date
    /// Время изменения; у неотредактированного сообщения равно `createdAt`.
    let updatedAt: Date

    var id: Int { messageId }
}

extension Message: Decodable {
    private enum CodingKeys: String, CodingKey {
        case messageId, clientId, conversationId, blockId, senderId, type, text, isEdited, createdAt, updatedAt
    }

    /// Разбирает сообщение; `createdAt` и `updatedAt` приходят Unix timestamp в секундах.
    /// Объявлен в extension, чтобы у структуры остался memberwise init.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decode(Int.self, forKey: .messageId)
        clientId = try container.decode(String.self, forKey: .clientId)
        conversationId = try container.decode(Int.self, forKey: .conversationId)
        blockId = try container.decode(Int.self, forKey: .blockId)
        senderId = try container.decode(Int.self, forKey: .senderId)
        type = try container.decode(MessageType.self, forKey: .type)
        text = try container.decode(String.self, forKey: .text)
        isEdited = try container.decode(Bool.self, forKey: .isEdited)
        createdAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .createdAt))
        updatedAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .updatedAt))
    }
}

extension Message {
    /// `true`, если эта версия сообщения не старше `other` — её можно применять поверх `other`.
    /// При равном `updatedAt` версии равноправны, и повторное применение ничего не меняет.
    /// - Parameter other: уже известная версия того же сообщения.
    func isNotOlder(than other: Message) -> Bool {
        updatedAt >= other.updatedAt
    }

    /// Ключ сопоставления с локальным неотправленным сообщением.
    var clientKey: MessageClientKey {
        MessageClientKey(senderId: senderId, clientId: clientId)
    }
}

/// Отправитель и `clientId` сообщения — ключ, общий у локального сообщения в очереди отправки и у серверного
/// сообщения, созданного из него. `clientId` уникален только в пределах отправителя, поэтому сравнивается вместе
/// с `senderId`.
struct MessageClientKey: Hashable {
    let senderId: Int
    let clientId: String
}
