//
//  MessagesBlockTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessagesBlockTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: пример ответа `/messages/getBlock` из документации — сообщения в поле `messages`.
    /// Ожидание: сообщения разобраны из обёртки.
    func test_decode_readsMessagesFromWrapper() throws {
        let json = """
        {
          "messages": [
            {
              "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
              "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
            }
          ]
        }
        """

        let block = try decoder.decode(MessagesBlock.self, from: Data(json.utf8))

        XCTAssertEqual(block.messages, [.stub])
    }

    /// Кейс: в ответе нет поля `messages`.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingMessages_throws() {
        let json = #"{"message":[]}"#

        XCTAssertThrowsError(try decoder.decode(MessagesBlock.self, from: Data(json.utf8)))
    }
}
