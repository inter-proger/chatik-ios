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
    /// Стек экранов поверх списка. Типизированный массив, а не `NavigationPath`: по нему список узнаёт,
    /// какая переписка сейчас открыта.
    var path: [ChatListRoute] = []
    /// Модальный экран поверх списка. `nil` — ничего не показано.
    var presentedSheet: ChatListSheet?

    /// Идентификатор переписки, экран которой открыт первым поверх списка. `nil` — поверх списка переписки нет.
    var openedConversationId: Int? {
        guard case let .conversation(conversation) = path.first else { return nil }
        return conversation.id
    }

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
