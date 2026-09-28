//
//  UserRowDisplayModel.swift
//  Chatik
//

import Foundation

/// Пользователь в списке выбора собеседника в готовом для отображения виде.
struct UserRowDisplayModel: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Логин с префиксом `@`.
    let login: String
    /// Аватар для списка — уменьшенная копия, если она есть. `nil` — аватар не установлен.
    let avatarURL: URL?
}

extension UserRowDisplayModel {
    init(user: User) {
        id = user.userId
        name = user.name
        login = "@\(user.login)"
        avatarURL = user.avatar.map { $0.smallURL ?? $0.url }
    }
}
