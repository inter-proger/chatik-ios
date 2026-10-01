//
//  APIAction.swift
//  Chatik
//

import Foundation

/// Указание клиенту из поля `actions` успешного ответа: `{ "type": "...", "data": { ... } }`.
/// Сервер будет добавлять новые типы, поэтому action неизвестного типа (или с неразборчивыми данными)
/// при разборе пропускается, а не ломает ответ — см. `APIResponse`.
enum APIAction: Equatable, Sendable {
    /// Пользователи, упомянутые в ответе (участники переписок, отправители сообщений): клиенту нужно
    /// иметь их в локальном кэше, чтобы показать имена и аватары. Id без повторов, по возрастанию;
    /// среди них может быть и текущий пользователь.
    case users(userIds: [Int])
}

extension APIAction {
    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private struct UsersData: Decodable {
        let userIds: [Int]
    }

    /// Разбирает один action.
    /// - Returns: `nil`, если тип клиенту неизвестен.
    /// - Throws: ошибку декодирования, если нет `type` или данные известного типа не соответствуют формату.
    static func decode(from decoder: Decoder) throws -> APIAction? {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "users":
            return .users(userIds: try container.decode(UsersData.self, forKey: .data).userIds)
        default:
            return nil
        }
    }
}

/// Элемент массива `actions`, разбор которого не бросает: неизвестный или битый action становится `nil`.
struct LossyAPIAction: Decodable {
    let action: APIAction?

    init(from decoder: Decoder) throws {
        action = try? APIAction.decode(from: decoder)
    }
}
