//
//  WebSocketMessagesTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class WebSocketMessagesTests: XCTestCase {
    private let decoder = JSONDecoder()

    private let messageJSON = """
    { "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
      "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000 }
    """

    private let lastMessageJSON = #"{ "messageId": 15, "type": "text", "text": "Привет!", "updatedAt": 1790846400000 }"#

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

    /// Кейс: `messages` / `received` из документации с `lastMessage` и `userIds`.
    /// Ожидание: сообщение и превью разобраны целиком, `userIds` прочитаны, подтверждение требуется.
    func test_decode_messageReceived() throws {
        let json = #"{"uid":"7d2b","group":"messages","event":"received","body":{"message":\#(messageJSON),"lastMessage":\#(lastMessageJSON)},"userIds":[1]}"#

        let message = try decode(json)

        XCTAssertEqual(message.uid, "7d2b")
        XCTAssertEqual(message.event, .messageReceived(.stub, .make(id: 15), nil))
        XCTAssertEqual(message.userIds, [1])
        XCTAssertTrue(message.requiresAcknowledgement)
    }

    /// Кейс: `received` без обязательного `lastMessage` — старый формат события.
    /// Ожидание: событие `.unknown` — разбор не падает, но и неполное событие не применяется.
    func test_decode_receivedWithoutLastMessage_isUnknown() throws {
        let message = try decode(#"{"uid":"1","group":"messages","event":"received","body":{"message":\#(messageJSON)}}"#)

        XCTAssertEqual(message.event, .unknown)
    }

    /// Кейс: `messages` / `edited` с `lastMessage` и без него, `conversations` / `singleCreated` в новом формате.
    /// Ожидание: события разобраны в соответствующие случаи; у `edited` без превью — `nil`.
    func test_decode_editedAndConversationCreated() throws {
        let conversationJSON = """
        { "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
          "opponentUserId": 2, "lastMessage": null, "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000,
          "unreadCount": 0, "lastReadMessageId": 0, "changeVersion": 1 }
        """
        let editedLast = try decode(#"{"uid":"1","group":"messages","event":"edited","body":{"message":\#(messageJSON),"lastMessage":\#(lastMessageJSON)}}"#)
        let edited = try decode(#"{"uid":"1","group":"messages","event":"edited","body":{"message":\#(messageJSON)}}"#)
        let created = try decode(#"{"uid":"2","group":"conversations","event":"singleCreated","body":{"conversation":\#(conversationJSON)},"userIds":[1,2]}"#)

        XCTAssertEqual(editedLast.event, .messageEdited(.stub, .make(id: 15), changeVersion: nil))
        XCTAssertEqual(edited.event, .messageEdited(.stub, nil, changeVersion: nil))
        XCTAssertEqual(edited.userIds, [])
        XCTAssertEqual(created.event, .conversationCreated(.singleStub))
    }

    /// Кейс: `conversations` / `read`, `received` с `readInfo` и `edited` с `changeVersion` — новые поля прочтения.
    /// Ожидание: прочтение разобрано в `ReadInfo`, версия правки — в `changeVersion`.
    func test_decode_readInfoFields() throws {
        let readInfoJSON = #"{"conversationId":1,"lastReadMessageId":15,"unreadCount":0,"totalUnreadCount":3,"changeVersion":118}"#
        let read = try decode(#"{"uid":"1","group":"conversations","event":"read","body":{"readInfo":\#(readInfoJSON)}}"#)
        let received = try decode(#"{"uid":"2","group":"messages","event":"received","body":{"message":\#(messageJSON),"lastMessage":\#(lastMessageJSON),"readInfo":\#(readInfoJSON)}}"#)
        let edited = try decode(#"{"uid":"3","group":"messages","event":"edited","body":{"message":\#(messageJSON),"lastMessage":\#(lastMessageJSON),"changeVersion":119}}"#)
        let expected = ReadInfo.make(conversationId: 1, lastRead: 15, unread: 0, total: 3, version: 118)

        XCTAssertEqual(read.event, .conversationRead(expected))
        XCTAssertTrue(read.requiresAcknowledgement)
        XCTAssertEqual(received.event, .messageReceived(.stub, .make(id: 15), expected))
        XCTAssertEqual(edited.event, .messageEdited(.stub, .make(id: 15), changeVersion: 119))
    }

    /// Кейс: `conversations` / `read` без обязательного поля `ReadInfo`.
    /// Ожидание: событие `.unknown` — разбор не падает, а неполное прочтение не применяется.
    func test_decode_readWithMalformedReadInfo_isUnknown() throws {
        let message = try decode(#"{"uid":"1","group":"conversations","event":"read","body":{"readInfo":{"conversationId":1,"unreadCount":0}}}"#)

        XCTAssertEqual(message.event, .unknown)
    }

    /// Кейс: `conversations` / `memberRead` с полным телом.
    /// Ожидание: событие `.memberRead` с переписокой, участником и указателем; подтверждение требуется.
    func test_decode_memberRead() throws {
        let message = try decode(#"{"uid":"1","group":"conversations","event":"memberRead","body":{"conversationId":1,"userId":2,"lastReadMessageId":15}}"#)

        XCTAssertEqual(message.event, .memberRead(conversationId: 1, userId: 2, lastReadMessageId: 15))
        XCTAssertTrue(message.requiresAcknowledgement)
    }

    /// Кейс: `conversations` / `memberRead` без обязательного поля `lastReadMessageId`.
    /// Ожидание: событие `.unknown` — неполный указатель не применяется.
    func test_decode_memberReadWithoutPointer_isUnknown() throws {
        let message = try decode(#"{"uid":"1","group":"conversations","event":"memberRead","body":{"conversationId":1,"userId":2}}"#)

        XCTAssertEqual(message.event, .unknown)
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
