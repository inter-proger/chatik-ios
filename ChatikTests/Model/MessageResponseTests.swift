//
//  MessageResponseTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageResponseTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: пример ответа `/messages/send` из документации — сообщение в поле `message`.
    /// Ожидание: сообщение разобрано из обёртки.
    func test_decode_readsMessageFromWrapper() throws {
        let json = """
        {
          "message": {
            "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
            "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
          }
        }
        """

        let response = try decoder.decode(MessageResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.message, .stub)
    }

    /// Кейс: в ответе нет поля `message`.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingMessage_throws() {
        let json = #"{"conversation":{}}"#

        XCTAssertThrowsError(try decoder.decode(MessageResponse.self, from: Data(json.utf8)))
    }
}
