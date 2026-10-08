//
//  MessagesPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessagesPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: пример ответа `/messages/getList` из документации — есть более старые блоки.
    /// Ожидание: сообщения разобраны, `nextBlockId` и `hasNext` — из ответа.
    func test_decode_readsMessagesAndNextBlockId() throws {
        let json = """
        {
          "messages": [
            {
              "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
              "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
            }
          ],
          "nextBlockId": 1,
          "hasNext": true
        }
        """

        let page = try decoder.decode(MessagesPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.messages, [.stub])
        XCTAssertEqual(page.nextBlockId, 1)
        XCTAssertTrue(page.hasNext)
    }

    /// Кейс: последняя страница — более старых блоков нет.
    /// Ожидание: `nextBlockId == nil`, следующей страницы нет.
    func test_decode_lastPage_hasNoNextBlockId() throws {
        let json = #"{"messages":[],"nextBlockId":null,"hasNext":false}"#

        let page = try decoder.decode(MessagesPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.messages.isEmpty)
        XCTAssertNil(page.nextBlockId)
        XCTAssertFalse(page.hasNext)
    }
}
