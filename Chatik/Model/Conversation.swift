//
//  Conversation.swift
//  Chatik
//

import Foundation

/// Тип переписки. Список будет расширяться: неизвестные значения читаются как `.unknown`,
/// чтобы новый тип с сервера не ломал разбор всего списка.
enum ConversationType: String, Decodable, Equatable {
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
struct Conversation: Decodable, Equatable, Identifiable {
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

    var id: Int { conversationId }
}
