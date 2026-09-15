//
//  ProfileEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/profile/*`. Все требуют активной сессии (cookie `PHPSESSID`).
enum ProfileEndpoint: Endpoint {
    /// GET /profile/get — профиль текущего пользователя. Ответ: `User`.
    case get
    /// POST /profile/setAvatar — установка аватара из ранее загруженного изображения. Ответ: обновлённый `User`.
    case setAvatar(fileId: Int)
    /// POST /profile/removeAvatar — удаление аватара (сам файл не удаляется). Ответ: обновлённый `User`.
    case removeAvatar

    var path: String {
        switch self {
        case .get: return "/profile/get"
        case .setAvatar: return "/profile/setAvatar"
        case .removeAvatar: return "/profile/removeAvatar"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .get: return .get
        case .setAvatar, .removeAvatar: return .post
        }
    }

    var parameters: [String: String] {
        switch self {
        case .get, .removeAvatar:
            return [:]
        case let .setAvatar(fileId):
            return ["file_id": String(fileId)]
        }
    }

    var headers: [String: String]? { nil }
}
