//
//  MessageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: сообщение из документации.
    /// Ожидание: все поля разобраны, `createdAt`/`updatedAt` прочитаны как Unix timestamp в секундах.
    func test_decode_readsAllFieldsAndUnixTimestamps() throws {
        let json = """
        {
          "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
          "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
        }
        """

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertEqual(message, .stub)
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, 1_790_846_400)
    }

    /// Кейс: отредактированное сообщение.
    /// Ожидание: `isEdited == true`, `updatedAt` отличается от `createdAt`.
    func test_decode_editedMessage_readsIsEditedAndUpdatedAt() throws {
        let json = """
        {
          "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет всем!",
          "isEdited": true, "createdAt": 1790846400, "updatedAt": 1790846460
        }
        """

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertEqual(message, .editedStub)
    }

    /// Кейс: сообщение используется как элемент списка.
    /// Ожидание: `id` совпадает с `messageId`.
    func test_id_matchesMessageId() {
        XCTAssertEqual(Message.stub.id, 15)
    }

    /// Кейс: сервер прислал тип сообщения, которого клиент ещё не знает.
    /// Ожидание: тип читается как `.unknown`, остальные поля разобраны — новый тип не ломает разбор списка.
    func test_decode_unknownType_fallsBackToUnknown() throws {
        let json = """
        {
          "messageId": 16, "conversationId": 1, "blockId": 2, "senderId": 2, "type": "sticker", "text": "",
          "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
        }
        """

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertEqual(message.type, .unknown)
        XCTAssertEqual(message.messageId, 16)
    }

    /// Кейс: в JSON нет обязательного поля `senderId`.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingRequiredField_throws() {
        let json = """
        {
          "messageId": 15, "conversationId": 1, "blockId": 2, "type": "text", "text": "Привет!",
          "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400
        }
        """

        XCTAssertThrowsError(try decoder.decode(Message.self, from: Data(json.utf8)))
    }
}
