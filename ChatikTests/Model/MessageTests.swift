//
//  MessageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: сообщение из документации.
    /// Ожидание: все поля разобраны, `createdAt`/`updatedAt` прочитаны как Unix timestamp в миллисекундах.
    func test_decode_readsAllFieldsAndUnixTimestamps() throws {
        let json = """
        {
          "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
          "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000
        }
        """

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertEqual(message, .stub)
        XCTAssertEqual(message.createdAt, ServerTime(milliseconds: 1_790_846_400_000))
    }

    /// Кейс: отредактированное сообщение.
    /// Ожидание: `isEdited == true`, `updatedAt` отличается от `createdAt`.
    func test_decode_editedMessage_readsIsEditedAndUpdatedAt() throws {
        let json = """
        {
          "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет всем!",
          "isEdited": true, "createdAt": 1790846400000, "updatedAt": 1790846460000
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
          "messageId": 16, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 2, "type": "sticker", "text": "",
          "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000
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
          "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "type": "text", "text": "Привет!",
          "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000
        }
        """

        XCTAssertThrowsError(try decoder.decode(Message.self, from: Data(json.utf8)))
    }

    /// Кейс: в JSON нет `clientId` — сервер обязан присылать его у всех сообщений.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingClientId_throws() {
        let json = """
        {
          "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
          "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000
        }
        """

        XCTAssertThrowsError(try decoder.decode(Message.self, from: Data(json.utf8)))
    }

    /// Кейс: ключ сопоставления с локальным сообщением.
    /// Ожидание: состоит из отправителя и `clientId`.
    func test_clientKey_combinesSenderAndClientId() {
        XCTAssertEqual(Message.stub.clientKey, MessageClientKey(senderId: 1, clientId: "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14"))
    }

    /// Кейс: время с миллисекундами, которые не представимы точно в `Double` секунд.
    /// Ожидание: прочитано ровно то целое, что прислал сервер.
    func test_decode_keepsMillisecondsExactly() throws {
        let json = """
        {
          "messageId": 15, "clientId": "c", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
          "isEdited": true, "createdAt": 1790846400123, "updatedAt": 1790846400999
        }
        """

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertEqual(message.createdAt.milliseconds, 1_790_846_400_123)
        XCTAssertEqual(message.updatedAt.milliseconds, 1_790_846_400_999)
    }

    /// Кейс: две версии одного сообщения, отличающиеся `updatedAt` на 1 мс, и одинаковые версии.
    /// Ожидание: более новая и равная версии «не старше», более старая — старше.
    func test_isNotOlder_comparesMilliseconds() {
        let current = Message.stub
        let newer = Message.editedStub

        XCTAssertTrue(newer.isNotOlder(than: current))
        XCTAssertTrue(current.isNotOlder(than: current))
        XCTAssertFalse(current.isNotOlder(than: newer))
    }
}
