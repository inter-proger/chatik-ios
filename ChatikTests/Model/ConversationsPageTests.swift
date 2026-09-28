//
//  ConversationsPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationsPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: страница из документации с одной личной перепиской.
    /// Ожидание: переписка разобрана вместе с собеседником, `hasNext` — из ответа.
    func test_decode_readsConversationsAndHasNext() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
              "opponentUser": { "userId": 2, "login": "petr", "name": "Petr Sidorov", "avatar": null }
            }
          ],
          "hasNext": false
        }
        """

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.conversations.map(\.conversationId), [1])
        XCTAssertEqual(page.conversations.first?.opponentUser?.login, "petr")
        XCTAssertFalse(page.hasNext)
    }

    /// Кейс: пустая страница со следующей страницей впереди.
    /// Ожидание: пустой список и `hasNext == true`.
    func test_decode_emptyPage_keepsHasNext() throws {
        let json = #"{"conversations":[],"hasNext":true}"#

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.conversations.isEmpty)
        XCTAssertTrue(page.hasNext)
    }
}
