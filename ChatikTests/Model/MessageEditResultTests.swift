//
//  MessageEditResultTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageEditResultTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: ответ `/messages/edit` по последнему сообщению переписки — с полем `lastMessage`.
    /// Ожидание: разобраны и сообщение, и превью.
    func test_decode_withLastMessage_readsBoth() throws {
        let json = """
        {
          "message": {
            "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет всем!",
            "isEdited": true, "createdAt": 1790846400000, "updatedAt": 1790846460000
          },
          "lastMessage": { "messageId": 15, "senderId": 1, "type": "text", "text": "Привет всем!", "updatedAt": 1790846460000 }
        }
        """

        let result = try decoder.decode(MessageEditResult.self, from: Data(json.utf8))

        XCTAssertEqual(result, MessageEditResult(message: .editedStub, lastMessage: LastMessage(message: .editedStub)))
    }

    /// Кейс: ответ `/messages/edit` по не последнему сообщению — поля `lastMessage` нет.
    /// Ожидание: сообщение разобрано, превью `nil`.
    func test_decode_withoutLastMessage_readsMessageOnly() throws {
        let json = """
        {
          "message": {
            "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет всем!",
            "isEdited": true, "createdAt": 1790846400000, "updatedAt": 1790846460000
          }
        }
        """

        let result = try decoder.decode(MessageEditResult.self, from: Data(json.utf8))

        XCTAssertEqual(result, MessageEditResult(message: .editedStub, lastMessage: nil))
    }
}
