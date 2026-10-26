//
//  ChatListRouter.swift
//  Chatik
//

import SwiftUI

/// Экраны, доступные из списка чатов.
enum ChatListRoute: Hashable {
    case profile
    case conversation(Conversation)
    /// Опции группы; переписка — запасной источник названия, описания и аватара, если её нет в списке.
    case groupOptions(Conversation)
    case groupMembers(conversationId: Int)
    case addGroupMembers(conversationId: Int)

    /// Переписка, к которой относится экран; `nil` — экран не переписки.
    var conversationId: Int? {
        switch self {
        case .profile: nil
        case let .conversation(conversation), let .groupOptions(conversation): conversation.conversationId
        case let .groupMembers(conversationId), let .addGroupMembers(conversationId): conversationId
        }
    }
}

/// Экраны, показываемые модально поверх списка чатов.
enum ChatListSheet: Identifiable {
    case createSingleConversation
    case createGroup

    var id: Self { self }
}

/// Роутер экрана списка чатов. Возврат к авторизации происходит через смену состояния сессии (`AppRouter`).
@MainActor
@Observable
final class ChatListRouter: ConversationOpening, GroupNavigating {
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

    /// Открывает переписку с любого экрана (нажатие на уведомление о сообщении): закрывает лист и заменяет стек —
    /// назад из переписки ведёт к списку. Если переписка уже открыта поверх списка, стек не меняется.
    /// - Parameter conversation: переписка, которую нужно показать.
    func openConversation(_ conversation: Conversation) {
        presentedSheet = nil
        guard openedConversationId != conversation.id else { return }
        path = [.conversation(conversation)]
    }

    /// Закрывает экраны переписки, если они есть в стеке: стек сбрасывается к списку — вместе с ним закрываются
    /// листы, показанные с этих экранов.
    /// - Parameter conversationId: переписка.
    /// - Returns: `true` — экраны переписки были открыты.
    @discardableResult
    func closeConversation(id conversationId: Int) -> Bool {
        guard path.contains(where: { $0.conversationId == conversationId }) else { return false }
        path = []
        return true
    }

    /// Открывает экран создания личного диалога.
    func showCreateSingleConversation() {
        presentedSheet = .createSingleConversation
    }

    /// Открывает экран создания группы.
    func showCreateGroup() {
        presentedSheet = .createGroup
    }

    // MARK: - GroupNavigating

    func showGroupOptions(_ conversation: Conversation) {
        path.append(.groupOptions(conversation))
    }

    func showGroupMembers(conversationId: Int) {
        path.append(.groupMembers(conversationId: conversationId))
    }

    func showAddGroupMembers(conversationId: Int) {
        path.append(.addGroupMembers(conversationId: conversationId))
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = []
    }

    /// Закрывает модальный экран.
    func dismissSheet() {
        presentedSheet = nil
    }
}
