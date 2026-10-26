//
//  GroupInfoTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class GroupInfoTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: `GroupInfo` из документации — владелец и участник.
    /// Ожидание: версия, роли и `joinedAfterMessageId` разобраны; владелец находится, участник ищется по id.
    func test_decode_readsMembersAndRoles() throws {
        let json = """
        {"conversationId": 12, "version": 4, "members": [
          {"userId": 1, "role": "member", "joinedAfterMessageId": 0},
          {"userId": 2, "role": "owner", "joinedAfterMessageId": 318}
        ]}
        """

        let info = try decoder.decode(GroupInfo.self, from: Data(json.utf8))

        XCTAssertEqual(info.conversationId, 12)
        XCTAssertEqual(info.version, 4)
        XCTAssertEqual(info.owner, GroupMember(userId: 2, role: .owner, joinedAfterMessageId: 318))
        XCTAssertEqual(info.member(userId: 1)?.role, .member)
        XCTAssertNil(info.member(userId: 3))
    }

    /// Кейс: сервер прислал роль, которой клиент ещё не знает (будущие модераторы).
    /// Ожидание: роль читается как `.member` — так требует сервер.
    func test_decode_unknownRole_readsAsMember() throws {
        let json = #"{"userId": 5, "role": "moderator", "joinedAfterMessageId": 0}"#

        let member = try decoder.decode(GroupMember.self, from: Data(json.utf8))

        XCTAssertEqual(member.role, .member)
    }

    /// Кейс: права ролей.
    /// Ожидание: добавлять участников и передавать права может только владелец.
    func test_roleRights_onlyOwner() {
        XCTAssertTrue(GroupRole.owner.canAddMembers)
        XCTAssertTrue(GroupRole.owner.canTransferOwnership)
        XCTAssertFalse(GroupRole.member.canAddMembers)
        XCTAssertFalse(GroupRole.member.canTransferOwnership)
    }

    /// Кейс: ответ `/groups/addMembers` из документации.
    /// Ожидание: добавленные, не добавленные с кодами и новый состав разобраны.
    func test_decode_addMembersResult() throws {
        let json = """
        {"addedUserIds": [2, 5],
         "notAddedUsersInfo": [{"userId": 1, "errorCode": 5006}, {"userId": 999, "errorCode": 4001}],
         "groupInfo": {"conversationId": 12, "version": 2, "members": [{"userId": 1, "role": "owner", "joinedAfterMessageId": 0}]}}
        """

        let result = try decoder.decode(AddMembersResult.self, from: Data(json.utf8))

        XCTAssertEqual(result.addedUserIds, [2, 5])
        XCTAssertEqual(result.notAddedUsersInfo, [UserErrorInfo(userId: 1, errorCode: 5006), UserErrorInfo(userId: 999, errorCode: 4001)])
        XCTAssertEqual(result.groupInfo.version, 2)
    }

    /// Кейс: ответ `/groups/leave`.
    /// Ожидание: метка удаления и общий счётчик разобраны.
    func test_decode_conversationRemoval() throws {
        let json = #"{"removedConversation": {"conversationId": 12, "changeVersion": 131}, "totalUnreadCount": 3}"#

        let removal = try decoder.decode(ConversationRemoval.self, from: Data(json.utf8))

        XCTAssertEqual(removal, ConversationRemoval(removedConversation: RemovedConversation(conversationId: 12, changeVersion: 131), totalUnreadCount: 3))
    }
}
