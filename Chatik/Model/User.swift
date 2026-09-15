//
//  User.swift
//  Chatik
//

import Foundation

/// Объект `User` из API — профиль пользователя (ответ `/profile/*`).
struct User: Decodable, Equatable {
    let userId: Int
    let login: String
    let name: String
    /// Аватар — файл типа `image`; `nil`, если не установлен.
    let avatar: RemoteFile?

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case login
        case name
        case avatar
    }
}
