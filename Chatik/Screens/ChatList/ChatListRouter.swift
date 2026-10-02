//
//  ChatListRouter.swift
//  Chatik
//

import SwiftUI

/// Экраны, доступные из списка чатов.
enum ChatListRoute: Hashable {
    case profile
    case conversation(Conversation)
}

/// Экраны, показываемые модально поверх списка чатов.
enum ChatListSheet: Identifiable {
    case createSingleConversation

    var id: Self { self }
}

/// Роутер экрана списка чатов. Возврат к авторизации происходит через смену состояния сессии (`AppRouter`).
@MainActor
@Observable
final class ChatListRouter {
    var path = NavigationPath()
    /// Модальный экран поверх списка. `nil` — ничего не показано.
    var presentedSheet: ChatListSheet?

    /// Открывает экран профиля текущего пользователя.
    func showProfile() {
        path.append(ChatListRoute.profile)
    }

    /// Открывает экран переписки.
    /// - Parameter conversation: переписка, которую нужно показать.
    func showConversation(_ conversation: Conversation) {
        path.append(ChatListRoute.conversation(conversation))
    }

    /// Открывает экран создания личного диалога.
    func showCreateSingleConversation() {
        presentedSheet = .createSingleConversation
    }

    /// Закрывает модальный экран.
    func dismissSheet() {
        presentedSheet = nil
    }
}
