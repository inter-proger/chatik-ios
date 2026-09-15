//
//  ChatListRouter.swift
//  Chatik
//

import SwiftUI

/// Экраны, доступные из списка чатов.
enum ChatListRoute: Hashable {
    case profile
}

/// Роутер экрана списка чатов. Возврат к авторизации происходит через смену состояния сессии (`AppRouter`).
@MainActor
@Observable
final class ChatListRouter {
    var path = NavigationPath()

    /// Открывает экран профиля текущего пользователя.
    func showProfile() {
        path.append(ChatListRoute.profile)
    }
}
