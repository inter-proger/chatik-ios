//
//  User.swift
//  Chatik
//

import Foundation

/// Объект `User` из API — профиль пользователя. Возвращается `/auth/signup`, `/auth/login` и `/profile/*`;
/// залогиненный пользователь хранится в `UserDefaults`.
struct User: Codable, Equatable, Identifiable {
    let userId: Int
    let login: String
    let name: String
    /// Аватар — файл типа `image`; `nil`, если не установлен.
    let avatar: RemoteFile?

    var id: Int { userId }
}
