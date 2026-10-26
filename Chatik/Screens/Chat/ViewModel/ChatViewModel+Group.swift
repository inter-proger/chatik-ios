//
//  ChatViewModel+Group.swift
//  Chatik
//

import Foundation

/// Группа на экране переписки: шестерёнка опций и плавающая панель «В группе нет других участников»
/// (`docs/group-chats.md`, решение 11).
extension ChatViewModel {
    /// Показывать ли шестерёнку опций группы.
    var isGroupOptionsButtonVisible: Bool {
        conversation.type == .group && groupNavigator != nil
    }

    /// Показывать ли панель «В группе нет других участников»: состав известен, в нём только текущий пользователь,
    /// у него есть право добавлять участников, и панель не скрыта. Пока состав неизвестен, панели нет — она не должна
    /// мелькать при открытии группы, где участники есть.
    var isEmptyGroupPanelVisible: Bool {
        guard conversation.type == .group, !isEmptyGroupPanelDismissed,
              let info = groupInfo?.groupInfo(conversationId: conversation.conversationId),
              let currentUserId = sessionService.currentUser?.userId,
              info.members.count == 1, let member = info.member(userId: currentUserId) else { return false }
        return member.role.canAddMembers
    }

    /// Шестерёнка: опции группы.
    func didTapGroupOptions() {
        groupNavigator?.showGroupOptions(conversation)
    }

    /// «Добавить» на панели: экран добавления участников.
    func didTapAddMembersOnPanel() {
        groupNavigator?.showAddGroupMembers(conversationId: conversation.conversationId)
    }

    /// Крестик на панели: скрывает её до следующего входа в переписку.
    func didDismissEmptyGroupPanel() {
        isEmptyGroupPanelDismissed = true
    }
}
