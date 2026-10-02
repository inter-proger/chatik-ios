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
    /// Время изменения полей переписки (состав, название, аватар); новые сообщения его не меняют.
    /// Из двух версий одной переписки (ответ REST, событие WebSocket) актуальна та, у которой он больше.
    let updatedAt: Date

    var id: Int { conversationId }
}

extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case conversationId, type, memberIds, name, avatar, opponentUserId, updatedAt
    }

    /// Разбирает переписку; `updatedAt` приходит Unix timestamp в секундах.
    /// Объявлен в extension, чтобы у структуры остался memberwise init.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(Int.self, forKey: .conversationId)
        type = try container.decode(ConversationType.self, forKey: .type)
        memberIds = try container.decode([Int].self, forKey: .memberIds)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(RemoteFile.self, forKey: .avatar)
        opponentUserId = try container.decodeIfPresent(Int.self, forKey: .opponentUserId)
        updatedAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .updatedAt))
    }
}

extension Conversation {
    /// `true`, если эта версия переписки не старше `other` — её можно применять поверх `other`.
    /// При равном `updatedAt` версии равноправны, и повторное применение ничего не меняет.
    /// - Parameter other: уже известная версия той же переписки.
    func isNotOlder(than other: Conversation) -> Bool {
        updatedAt >= other.updatedAt
    }
}
