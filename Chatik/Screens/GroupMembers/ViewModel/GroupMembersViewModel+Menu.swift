//
//  GroupMembersViewModel+Menu.swift
//  Chatik
//

import Foundation

/// Пункты меню участника по роли текущего пользователя (`docs/group-chats.md`, решения 18–20).
extension GroupMembersViewModel {
    /// Роль текущего пользователя; `nil` — состав неизвестен или пользователя в нём нет.
    private var currentRole: GroupRole? {
        guard let userId = sessionService.currentUser?.userId else { return nil }
        return info?.member(userId: userId)?.role
    }

    /// Пункты меню участника по порядку; пусто — меню нет (своя строка или идёт запрос).
    /// - Parameter member: строка участника.
    func actions(for member: GroupMemberDisplayModel) -> [GroupMemberAction] {
        guard !isPerformingAction, !member.isCurrentUser else { return [] }
        var actions: [GroupMemberAction] = [.directChat]
        if currentRole?.canTransferOwnership == true {
            actions.append(.transferOwnership)
        }
        if currentRole?.canRemoveMembers == true {
            actions.append(.remove)
        }
        return actions
    }
}
