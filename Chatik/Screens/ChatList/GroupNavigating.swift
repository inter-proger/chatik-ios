//
//  GroupNavigating.swift
//  Chatik
//

import Foundation

/// Переходы экранов группы — узкий протокол роутера списка чатов для экрана переписки и экранов группы.
@MainActor
protocol GroupNavigating: AnyObject {
    /// Открывает опции группы.
    /// - Parameter conversation: группа — снимок для показа, если её нет в списке.
    func showGroupOptions(_ conversation: Conversation)
    /// Открывает участников группы.
    /// - Parameter conversationId: группа.
    func showGroupMembers(conversationId: Int)
    /// Открывает добавление участников.
    /// - Parameter conversationId: группа.
    func showAddGroupMembers(conversationId: Int)
    /// Открывает переписку вместо стека экранов: «Назад» из неё ведёт к списку чатов.
    /// - Parameter conversation: переписка.
    func openConversation(_ conversation: Conversation)
    /// Закрывает верхний экран.
    func pop()
    /// Возвращает к списку чатов.
    func popToRoot()
}
