//
//  WebSocketMessages.swift
//  Chatik
//

import Foundation

/// Событие сервера, разобранное по паре `group` / `event`.
enum WebSocketServerEvent: Equatable, Sendable {
    /// `auth` / `connected` — соединение авторизовано, дальше сервер присылает события.
    case connected
    /// `auth` / `connectionError` — авторизация не удалась; следом сервер закроет соединение с кодом 4001.
    /// `nil` — код ошибки не разобран.
    case connectionError(errorCode: Int?)
    /// `conversations` / `singleCreated` — создана личная переписка (с точки зрения получателя).
    case conversationCreated(Conversation)
    /// `conversations` / `read` — переписка прочитана (на этом или другом устройстве).
    case conversationRead(ReadInfo)
    /// `conversations` / `memberRead` — другой участник сдвинул указатель прочтения переписки.
    case memberRead(conversationId: Int, userId: Int, lastReadMessageId: Int)
    /// `messages` / `received` — новое сообщение, новое превью переписки и прочтение для получателя.
    /// `nil` — прочтения в событии нет.
    case messageReceived(Message, LastMessage, ReadInfo?)
    /// `messages` / `edited` — сообщение отредактировано; превью и версия пользователя — только если отредактировано
    /// последнее сообщение.
    case messageEdited(Message, LastMessage?, changeVersion: Int?)
    /// Событие, которого клиент не знает, или известное событие с неразборчивыми данными: игнорируется,
    /// но подтверждается — сервер будет добавлять новые события.
    case unknown
}

/// Сообщение сервера: `{ "uid", "group", "event", "body", "userIds" }`.
struct WebSocketServerMessage: Equatable, Sendable {
    /// Группа событий авторизации: на её события подтверждение не отправляется.
    static let authGroup = "auth"

    /// Идентификатор сообщения — его возвращают в подтверждении получения.
    let uid: String
    let group: String
    let event: WebSocketServerEvent
    /// Пользователи, фигурирующие в событии; обрабатываются как action `users`. Пустой, если поля нет.
    let userIds: [Int]

    /// `true`, если на сообщение нужно ответить `events` / `received`: на всё, кроме группы `auth`.
    var requiresAcknowledgement: Bool {
        group != Self.authGroup
    }
}

extension WebSocketServerMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case uid, group, event, body, userIds
    }

    private struct ConnectionErrorBody: Decodable {
        let errorCode: Int
    }

    private struct ConversationBody: Decodable {
        let conversation: Conversation
    }

    private struct ReadBody: Decodable {
        let readInfo: ReadInfo
    }

    private struct MemberReadBody: Decodable {
        let conversationId: Int
        let userId: Int
        let lastReadMessageId: Int
    }

    private struct ReceivedBody: Decodable {
        let message: Message
        let lastMessage: LastMessage
        let readInfo: ReadInfo?
    }

    private struct EditedBody: Decodable {
        let message: Message
        let lastMessage: LastMessage?
        let changeVersion: Int?
    }

    /// Разбирает сообщение. Заголовок (`uid`, `group`, `event`) обязателен; данные известного события, которые
    /// не разобрались, делают событие `.unknown`, а не ломают разбор: его всё равно нужно подтвердить.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        group = try container.decode(String.self, forKey: .group)
        let eventName = try container.decode(String.self, forKey: .event)
        userIds = (try? container.decodeIfPresent([Int].self, forKey: .userIds)) ?? []
        event = Self.decodeEvent(group: group, event: eventName, from: container) ?? .unknown
    }

    /// Разбирает `body` известного события.
    /// - Returns: `nil`, если событие неизвестно или его данные не разобрались.
    private static func decodeEvent(
        group: String,
        event: String,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> WebSocketServerEvent? {
        switch (group, event) {
        case ("auth", "connected"):
            return .connected
        case ("auth", "connectionError"):
            return .connectionError(errorCode: (try? container.decode(ConnectionErrorBody.self, forKey: .body))?.errorCode)
        case ("conversations", "singleCreated"):
            return (try? container.decode(ConversationBody.self, forKey: .body)).map { .conversationCreated($0.conversation) }
        case ("conversations", "read"):
            return (try? container.decode(ReadBody.self, forKey: .body)).map { .conversationRead($0.readInfo) }
        case ("conversations", "memberRead"):
            return (try? container.decode(MemberReadBody.self, forKey: .body)).map {
                .memberRead(conversationId: $0.conversationId, userId: $0.userId, lastReadMessageId: $0.lastReadMessageId)
            }
        case ("messages", "received"):
            return (try? container.decode(ReceivedBody.self, forKey: .body)).map {
                .messageReceived($0.message, $0.lastMessage, $0.readInfo)
            }
        case ("messages", "edited"):
            return (try? container.decode(EditedBody.self, forKey: .body)).map {
                .messageEdited($0.message, $0.lastMessage, changeVersion: $0.changeVersion)
            }
        default:
            return nil
        }
    }
}

/// Сообщение клиента серверу.
enum WebSocketClientMessage: Equatable, Sendable {
    /// `auth` / `connect` — авторизация соединения; должно быть первым сообщением.
    case authConnect(userId: Int, token: String)
    /// `events` / `received` — подтверждение получения события сервера с указанным `uid`.
    case acknowledge(receivedUid: String)
}

extension WebSocketClientMessage {
    private struct Envelope<Body: Encodable>: Encodable {
        let uid: String
        let group: String
        let event: String
        let body: Body
    }

    private struct AuthConnectBody: Encodable {
        let userId: Int
        let token: String
    }

    private struct AcknowledgeBody: Encodable {
        let receivedUid: String
    }

    /// Собирает JSON сообщения; `uid` — новый UUID v4 на каждый вызов.
    /// - Parameter uid: идентификатор сообщения; подменяется в тестах.
    func encoded(uid: String = UUID().uuidString.lowercased()) throws -> String {
        let data: Data
        switch self {
        case let .authConnect(userId, token):
            data = try JSONEncoder().encode(Envelope(uid: uid, group: "auth", event: "connect", body: AuthConnectBody(userId: userId, token: token)))
        case let .acknowledge(receivedUid):
            data = try JSONEncoder().encode(Envelope(uid: uid, group: "events", event: "received", body: AcknowledgeBody(receivedUid: receivedUid)))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
