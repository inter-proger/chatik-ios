//
//  GroupNavigatingMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок переходов экранов группы: запоминает вызовы по порядку.
@MainActor
final class GroupNavigatingMock: GroupNavigating {
    /// Вызовы: `"options 2"`, `"members 2"`, `"add 2"`, `"pop"`, `"root"`.
    private(set) var calls: [String] = []

    func showGroupOptions(_ conversation: Conversation) {
        calls.append("options \(conversation.conversationId)")
    }

    func showGroupMembers(conversationId: Int) {
        calls.append("members \(conversationId)")
    }

    func showAddGroupMembers(conversationId: Int) {
        calls.append("add \(conversationId)")
    }

    func openConversation(_ conversation: Conversation) {
        calls.append("open \(conversation.conversationId)")
    }

    func pop() {
        calls.append("pop")
    }

    func popToRoot() {
        calls.append("root")
    }
}

extension GroupInfo {
    /// Состав группы 2: владелец и участники с указанными id.
    /// - Parameters:
    ///   - ownerId: владелец.
    ///   - memberIds: остальные участники.
    ///   - version: версия состава.
    static func make(ownerId: Int = 1, memberIds: [Int] = [], version: Int = 1, conversationId: Int = 2) -> GroupInfo {
        GroupInfo(
            conversationId: conversationId,
            version: version,
            members: [GroupMember(userId: ownerId, role: .owner, joinedAfterMessageId: 0)]
                + memberIds.map { GroupMember(userId: $0, role: .member, joinedAfterMessageId: 0) }
        )
    }
}
