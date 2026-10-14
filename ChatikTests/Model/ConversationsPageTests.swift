//
//  ConversationsPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationsPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: страница из документации с одной личной перепиской.
    /// Ожидание: переписка разобрана вместе с id собеседника, `hasNext` — из ответа.
    func test_decode_readsConversationsAndHasNext() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
              "opponentUserId": 2, "lastMessage": null, "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000
            }
          ],
          "hasNext": false
        }
        """

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.conversations.map(\.conversationId), [1])
        XCTAssertEqual(page.conversations.first?.opponentUserId, 2)
        XCTAssertFalse(page.hasNext)
    }
}
