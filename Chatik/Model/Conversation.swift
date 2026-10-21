//
//  Conversation.swift
//  Chatik
//

import Foundation

/// Тип переписки. Список будет расширяться: неизвестные значения читаются как `.unknown`,
/// чтобы новый тип с сервера не ломал разбор всего списка.
enum ConversationType: String, Decodable, Hashable {
    /// Личная переписка двух пользователей: без названия и аватара.
    case single
    /// Групповая переписка: может иметь название и аватар.
    case group
    /// Тип, которого клиент ещё не знает.
    case unknown

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ConversationType(rawValue: rawValue) ?? .unknown
    }
}

/// Объект `Conversation` из API — переписка, в которой состоит текущий пользователь.
/// `Hashable` — переписка передаётся в маршрут навигации к экрану чата.
///
/// У переписки три независимые версии: **позиция** в списке (`positionUpdatedAt` вместе с `lastMessage`),
/// **информация** (`updatedInfoAt`) и **прочтение** (`readState.changeVersion`). Версии сливаются по правилам
/// `ConversationMerger`.
struct Conversation: Hashable, Identifiable {
    let conversationId: Int
    let type: ConversationType
    /// Идентификаторы участников по возрастанию.
    let memberIds: [Int]
    /// Название — только у `group`; у `single` всегда `nil`.
    let name: String?
    /// Аватар — файл типа `image`; только у `group`, у `single` всегда `nil`.
    let avatar: RemoteFile?
    /// Id собеседника — второго участника относительно текущего пользователя; только у `single`,
    /// у `group` всегда `nil`. Имя и аватар берутся из кэша пользователей: сервер присылает id собеседника
    /// в action `users` того же ответа.
    let opponentUserId: Int?
    /// Последнее сообщение; `nil`, пока сообщений нет или если последнее сообщение удалено.
    let lastMessage: LastMessage?
    /// Когда переписка последний раз поднялась: `createdAt` последнего сообщения, до первого сообщения — время
    /// создания переписки. По нему сортируется список.
    let positionUpdatedAt: ServerTime
    /// Когда менялось то, что не двигает переписку: участники, название, аватар и текст последнего сообщения.
    let updatedInfoAt: ServerTime
    /// Прочтение для текущего пользователя; в JSON — поля `unreadCount`, `lastReadMessageId`, `changeVersion`
    /// на верхнем уровне переписки.
    let readState: ConversationReadState

    var id: Int { conversationId }

    /// Версия позиции — для правила 1 слияния.
    var position: ConversationPosition {
        ConversationPosition(positionUpdatedAt: positionUpdatedAt, messageId: lastMessage?.messageId ?? 0)
    }
}

extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case conversationId, type, memberIds, name, avatar, opponentUserId, lastMessage, positionUpdatedAt, updatedInfoAt
        case unreadCount, lastReadMessageId, changeVersion
    }

    /// Разбирает переписку; время приходит Unix timestamp в миллисекундах.
    /// Объявлен в extension, чтобы у структуры остался memberwise init.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(Int.self, forKey: .conversationId)
        type = try container.decode(ConversationType.self, forKey: .type)
        memberIds = try container.decode([Int].self, forKey: .memberIds)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(RemoteFile.self, forKey: .avatar)
        opponentUserId = try container.decodeIfPresent(Int.self, forKey: .opponentUserId)
        lastMessage = try container.decodeIfPresent(LastMessage.self, forKey: .lastMessage)
        positionUpdatedAt = try container.decode(ServerTime.self, forKey: .positionUpdatedAt)
        updatedInfoAt = try container.decode(ServerTime.self, forKey: .updatedInfoAt)
        readState = ConversationReadState(
            unreadCount: try container.decode(Int.self, forKey: .unreadCount),
            lastReadMessageId: try container.decode(Int.self, forKey: .lastReadMessageId),
            changeVersion: try container.decode(Int.self, forKey: .changeVersion)
        )
    }
}

extension Conversation {
    /// `true`, если переписка стоит в списке выше `other`: порядок — `positionUpdatedAt` по убыванию,
    /// при равенстве — `conversationId` по убыванию.
    /// - Parameter other: переписка, с которой сравнивается порядок.
    func isOrderedBefore(_ other: Conversation) -> Bool {
        guard positionUpdatedAt == other.positionUpdatedAt else { return positionUpdatedAt > other.positionUpdatedAt }
        return conversationId > other.conversationId
    }
}

/// Версия позиции переписки: пара `(positionUpdatedAt, lastMessage.messageId)`, сравнивается лексикографически.
/// При `lastMessage == nil` берётся `messageId = 0`.
struct ConversationPosition: Comparable, Hashable {
    let positionUpdatedAt: ServerTime
    let messageId: Int

    static func < (lhs: ConversationPosition, rhs: ConversationPosition) -> Bool {
        (lhs.positionUpdatedAt, lhs.messageId) < (rhs.positionUpdatedAt, rhs.messageId)
    }
}

/// Частичная версия переписки из событий `messages` и ответа `/messages/send`: позиция равна `createdAt`
/// сообщения, информации нет. Прочтение — только у `received` и ответа `send`.
struct ConversationPatch: Hashable {
    let conversationId: Int
    let positionUpdatedAt: ServerTime
    let lastMessage: LastMessage
    /// Прочтение и общий счётчик из того же события или ответа; `nil` — их нет (`edited`).
    var readInfo: ReadInfo?

    /// Версия позиции — для правила 1 слияния.
    var position: ConversationPosition {
        ConversationPosition(positionUpdatedAt: positionUpdatedAt, messageId: lastMessage.messageId)
    }
}

extension ConversationPatch {
    /// Патч по сообщению, ставшему последним в переписке.
    /// - Parameters:
    ///   - message: сообщение из события или ответа `/messages/send`.
    ///   - lastMessage: превью из события; по умолчанию — из самого сообщения.
    ///   - readInfo: прочтение из события `received` или ответа `send`.
    init(message: Message, lastMessage: LastMessage? = nil, readInfo: ReadInfo? = nil) {
        self.init(
            conversationId: message.conversationId,
            positionUpdatedAt: message.createdAt,
            lastMessage: lastMessage ?? LastMessage(message: message),
            readInfo: readInfo
        )
    }
}
