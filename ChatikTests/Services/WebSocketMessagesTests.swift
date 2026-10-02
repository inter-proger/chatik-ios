//
//  WebSocketMessagesTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class WebSocketMessagesTests: XCTestCase {
    private let decoder = JSONDecoder()

    private let messageJSON = """
    { "messageId": 15, "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
      "isEdited": false, "createdAt": 1790846400, "updatedAt": 1790846400 }
    """

    /// Разбирает сообщение сервера из JSON.
    private func decode(_ json: String) throws -> WebSocketServerMessage {
        try decoder.decode(WebSocketServerMessage.self, from: Data(json.utf8))
    }

    /// Кейс: `auth` / `connected` и `auth` / `connectionError` с кодом 2004.
    /// Ожидание: события разобраны; подтверждение для группы `auth` не требуется.
    func test_decode_authEvents() throws {
        let connected = try decode(#"{"uid":"1","group":"auth","event":"connected","body":{}}"#)
        let error = try decode(#"{"uid":"2","group":"auth","event":"connectionError","body":{"errorCode":2004}}"#)

        XCTAssertEqual(connected.event, .connected)
        XCTAssertEqual(error.event, .connectionError(errorCode: 2004))
        XCTAssertFalse(connected.requiresAcknowledgement)
        XCTAssertFalse(error.requiresAcknowledgement)
    }

    /// Кейс: `messages` / `received` из документации с `userIds`.
    /// Ожидание: сообщение разобрано целиком, `userIds` прочитаны, подтверждение требуется.
    func test_decode_messageReceived() throws {
        let json = #"{"uid":"7d2b","group":"messages","event":"received","body":{"message":\#(messageJSON)},"userIds":[1]}"#

        let message = try decode(json)

        XCTAssertEqual(message.uid, "7d2b")
        XCTAssertEqual(message.event, .messageReceived(.stub))
        XCTAssertEqual(message.userIds, [1])
        XCTAssertTrue(message.requiresAcknowledgement)
    }

    /// Кейс: `messages` / `edited` и `conversations` / `singleCreated`.
    /// Ожидание: события разобраны в соответствующие случаи.
    func test_decode_editedAndConversationCreated() throws {
        let conversationJSON = """
        { "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
          "opponentUserId": 2, "updatedAt": 1790846400 }
        """
        let edited = try decode(#"{"uid":"1","group":"messages","event":"edited","body":{"message":\#(messageJSON)}}"#)
        let created = try decode(#"{"uid":"2","group":"conversations","event":"singleCreated","body":{"conversation":\#(conversationJSON)},"userIds":[1,2]}"#)

        XCTAssertEqual(edited.event, .messageEdited(.stub))
        XCTAssertEqual(edited.userIds, [])
        XCTAssertEqual(created.event, .conversationCreated(.singleStub))
    }

    /// Кейс: неизвестное событие и известное событие с неразборчивыми данными.
    /// Ожидание: оба — `.unknown`, разбор не падает, подтверждение требуется.
    func test_decode_unknownOrBrokenBody_isUnknown() throws {
        let unknown = try decode(#"{"uid":"1","group":"typing","event":"started","body":{"x":1}}"#)
        let broken = try decode(#"{"uid":"2","group":"messages","event":"received","body":{"message":{"messageId":"x"}}}"#)

        XCTAssertEqual(unknown.event, .unknown)
        XCTAssertEqual(broken.event, .unknown)
        XCTAssertTrue(unknown.requiresAcknowledgement)
        XCTAssertTrue(broken.requiresAcknowledgement)
    }

    /// Кейс: в сообщении нет обязательного заголовка — `uid`, `group` или `event`.
    /// Ожидание: ошибка разбора.
    func test_decode_missingHeader_throws() {
        let jsons = [
            #"{"group":"auth","event":"connected","body":{}}"#,
            #"{"uid":"1","event":"connected","body":{}}"#,
            #"{"uid":"1","group":"auth","body":{}}"#,
        ]

        for json in jsons {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    /// Кейс: клиент собирает `auth` / `connect` и `events` / `received`.
    /// Ожидание: JSON соответствует протоколу — `uid`, `group`, `event`, `body`.
    func test_encode_clientMessages() throws {
        let auth = try WebSocketClientMessage.authConnect(userId: 1, token: "abc").encoded(uid: "u1")
        let ack = try WebSocketClientMessage.acknowledge(receivedUid: "e1").encoded(uid: "u2")

        let authObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(auth.utf8)) as? NSDictionary)
        let ackObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ack.utf8)) as? NSDictionary)
        XCTAssertEqual(authObject, ["uid": "u1", "group": "auth", "event": "connect", "body": ["userId": 1, "token": "abc"]])
        XCTAssertEqual(ackObject, ["uid": "u2", "group": "events", "event": "received", "body": ["receivedUid": "e1"]])
    }

    /// Кейс: два сообщения клиента собраны без явного `uid`.
    /// Ожидание: у каждого свой UUID.
    func test_encode_generatesUniqueUid() throws {
        let first = try WebSocketClientMessage.acknowledge(receivedUid: "e").encoded()
        let second = try WebSocketClientMessage.acknowledge(receivedUid: "e").encoded()

        let firstUid = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])?["uid"] as? String)
        let secondUid = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(second.utf8)) as? [String: Any])?["uid"] as? String)
        XCTAssertNotNil(UUID(uuidString: firstUid))
        XCTAssertNotEqual(firstUid, secondUid)
    }
}
