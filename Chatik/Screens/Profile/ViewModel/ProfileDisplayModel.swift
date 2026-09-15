//
//  ProfileDisplayModel.swift
//  Chatik
//

import Foundation

/// Данные профиля в готовом для отображения виде.
struct ProfileDisplayModel: Equatable {
    let name: String
    let login: String
    /// Идентификатор пользователя как текст.
    let userId: String
    /// Полноразмерный аватар; `nil` — аватар не установлен.
    let avatarURL: URL?
    /// Уменьшенная копия аватара — показывается, пока грузится полноразмерная. `nil` — копии нет.
    let avatarThumbnailURL: URL?
}

extension ProfileDisplayModel {
    init(user: User) {
        name = user.name
        login = user.login
        userId = String(user.userId)
        avatarURL = user.avatar?.url
        avatarThumbnailURL = user.avatar?.smallURL
    }
}
