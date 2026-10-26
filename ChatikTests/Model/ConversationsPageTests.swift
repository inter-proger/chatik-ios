//
//  ConversationsPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationsPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: страница из документации с одной личной перепиской.
    /// Ожидание: переписка разобрана вместе с id собеседника; `hasNext`, общий счётчик и версия — из ответа.
    func test_decode_readsConversationsAndHasNext() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
              "opponentUserId": 2, "lastMessage": null, "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000,
              "unreadCount": 2, "lastReadMessageId": 7, "changeVersion": 120
            }
          ],
          "hasNext": false,
          "totalUnreadCount": 5,
          "changeVersion": 121
        }
        """

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.conversations.map(\.conversationId), [1])
        XCTAssertEqual(page.conversations.first?.opponentUserId, 2)
        XCTAssertFalse(page.hasNext)
        XCTAssertEqual(page.totalUnreadCount, 5)
        XCTAssertEqual(page.changeVersion, 121)
        XCTAssertTrue(page.removedConversations.isEmpty)
    }

    /// Кейс: страница `changedAfter` с перепиской на версии 130 и меткой удаления на версии 131.
    /// Ожидание: метка разобрана; наибольшая версия страницы — по обеим частям, 131.
    func test_decode_removedConversations_countInMaxVersion() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
              "opponentUserId": 2, "lastMessage": null, "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000,
              "unreadCount": 0, "lastReadMessageId": 0, "changeVersion": 130
            }
          ],
          "removedConversations": [{ "conversationId": 12, "changeVersion": 131 }],
          "hasNext": false,
          "totalUnreadCount": 0,
          "changeVersion": 131
        }
        """

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.removedConversations, [RemovedConversation(conversationId: 12, changeVersion: 131)])
        XCTAssertEqual(page.maxItemChangeVersion, 131)
    }
}
