//
//  ConversationTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: личная переписка из документации — без названия и аватара, с id собеседника и последним сообщением.
    /// Ожидание: поля разобраны, `type == .single`, `name` и `avatar` — `nil`, `opponentUserId` и `lastMessage`
    /// прочитаны, время — в миллисекундах; поля прочтения верхнего уровня собраны в `readState`.
    func test_decode_single_readsMembersOpponentAndLastMessage() throws {
        let json = """
        {
          "conversationId": 7, "type": "single", "memberIds": [1, 5], "name": null, "avatar": null, "opponentUserId": 5,
          "lastMessage": { "messageId": 15, "type": "text", "text": "Привет!", "updatedAt": 1790846400123 },
          "positionUpdatedAt": 1790846400123, "updatedInfoAt": 1790846000456,
          "unreadCount": 3, "lastReadMessageId": 12, "changeVersion": 118
        }
        """

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.conversationId, 7)
        XCTAssertEqual(conversation.type, .single)
        XCTAssertEqual(conversation.memberIds, [1, 5])
        XCTAssertNil(conversation.name)
        XCTAssertNil(conversation.avatar)
        XCTAssertEqual(conversation.opponentUserId, 5)
        XCTAssertEqual(conversation.lastMessage, LastMessage(messageId: 15, type: .text, text: "Привет!", updatedAt: ServerTime(milliseconds: 1_790_846_400_123)))
        XCTAssertEqual(conversation.positionUpdatedAt, ServerTime(milliseconds: 1_790_846_400_123))
        XCTAssertEqual(conversation.updatedInfoAt, ServerTime(milliseconds: 1_790_846_000_456))
        XCTAssertEqual(conversation.readState, ConversationReadState(unreadCount: 3, lastReadMessageId: 12, changeVersion: 118))
    }

    /// Кейс: групповая переписка с названием и аватаром-изображением, без сообщений (`lastMessage: null`).
    /// Ожидание: `type == .group`, название прочитано, аватар разобран как `RemoteFile`, `lastMessage == nil`.
    func test_decode_group_readsNameAndAvatar() throws {
        let json = """
        {
          "conversationId": 7, "type": "group", "memberIds": [1, 2, 3], "name": "Команда", "opponentUserId": null,
          "lastMessage": null, "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000,
          "unreadCount": 0, "lastReadMessageId": 0, "changeVersion": 1,
          "avatar": {
            "fileId": 5, "type": "image", "url": "http://h/a.jpg", "size": 1, "filename": "a.jpg", "extension": "jpg",
            "data": { "smallUrl": "http://h/a_small.jpg" }
          }
        }
        """

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.type, .group)
        XCTAssertEqual(conversation.name, "Команда")
        XCTAssertEqual(conversation.avatar?.fileId, 5)
        XCTAssertEqual(conversation.avatar?.smallURL, URL(string: "http://h/a_small.jpg"))
        XCTAssertNil(conversation.opponentUserId)
        XCTAssertNil(conversation.lastMessage)
    }

    /// Кейс: у последнего сообщения тип, которого клиент не знает, и нет текста.
    /// Ожидание: тип читается как `.unknown`, `text == nil` — переписка не теряется.
    func test_decode_lastMessageOfUnknownTypeWithoutText() throws {
        let json = """
        {
          "conversationId": 7, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null, "opponentUserId": 2,
          "lastMessage": { "messageId": 16, "type": "sticker", "text": null, "updatedAt": 1790846400000 },
          "positionUpdatedAt": 1790846400000, "updatedInfoAt": 1790846400000,
          "unreadCount": 0, "lastReadMessageId": 0, "changeVersion": 1
        }
        """

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.lastMessage?.type, .unknown)
        XCTAssertNil(conversation.lastMessage?.text)
    }

    /// Кейс: переписка используется как элемент списка.
    /// Ожидание: `id` совпадает с `conversationId`.
    func test_id_matchesConversationId() {
        XCTAssertEqual(Conversation.make(id: 42).id, 42)
    }

    /// Кейс: сервер прислал тип переписки, которого клиент ещё не знает.
    /// Ожидание: тип читается как `.unknown`, остальные поля разобраны — новый тип не ломает разбор списка.
    func test_decode_unknownType_fallsBackToUnknown() throws {
        let json = #"{"conversationId":9,"type":"channel","memberIds":[1,2],"name":"Канал","avatar":null,"opponentUserId":null,"lastMessage":null,"positionUpdatedAt":1790846400000,"updatedInfoAt":1790846400000,"unreadCount":0,"lastReadMessageId":0,"changeVersion":1}"#

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.type, .unknown)
        XCTAssertEqual(conversation.conversationId, 9)
        XCTAssertEqual(conversation.name, "Канал")
    }

    /// Кейс: в JSON нет обязательного поля — `memberIds`, `positionUpdatedAt`, `updatedInfoAt` или полей прочтения;
    /// либо пришёл старый формат с `updatedAt` вместо новых полей.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingRequiredField_throws() {
        let jsons = [
            #"{"conversationId":1,"type":"single","name":null,"avatar":null,"opponentUserId":null,"positionUpdatedAt":1,"updatedInfoAt":1}"#,
            #"{"conversationId":1,"type":"single","memberIds":[1,2],"name":null,"avatar":null,"opponentUserId":null,"updatedInfoAt":1}"#,
            #"{"conversationId":1,"type":"single","memberIds":[1,2],"name":null,"avatar":null,"opponentUserId":null,"positionUpdatedAt":1}"#,
            #"{"conversationId":1,"type":"single","memberIds":[1,2],"name":null,"avatar":null,"opponentUserId":null,"updatedAt":1790846400}"#,
            #"{"conversationId":1,"type":"single","memberIds":[1,2],"name":null,"avatar":null,"opponentUserId":null,"positionUpdatedAt":1,"updatedInfoAt":1,"unreadCount":0,"lastReadMessageId":0}"#,
        ]

        for json in jsons {
            XCTAssertThrowsError(try decoder.decode(Conversation.self, from: Data(json.utf8)), json)
        }
    }

    /// Кейс: версия позиции у переписки без сообщений и с последним сообщением.
    /// Ожидание: без сообщений `messageId = 0`; сравнение лексикографическое — сначала время, затем `messageId`.
    func test_position_comparesTimeThenMessageId() {
        let empty = Conversation.make(id: 1, position: .stub)
        let withMessage = empty.with(position: .stub, lastMessage: .make(id: 15))
        let later = empty.with(position: .stub(1), lastMessage: .make(id: 3))

        XCTAssertEqual(empty.position, ConversationPosition(positionUpdatedAt: .stub, messageId: 0))
        XCTAssertLessThan(empty.position, withMessage.position)
        XCTAssertLessThan(withMessage.position, later.position)
    }

    /// Кейс: порядок переписок в списке — разные позиции и одинаковые позиции с разными id.
    /// Ожидание: выше та, что поднялась позже; при равной позиции — с большим `conversationId`.
    func test_isOrderedBefore_sortsByPositionThenId() {
        let older = Conversation.make(id: 9, position: .stub)
        let newer = Conversation.make(id: 1, position: .stub(1))
        let sameTimeBiggerId = Conversation.make(id: 10, position: .stub)

        XCTAssertTrue(newer.isOrderedBefore(older))
        XCTAssertFalse(older.isOrderedBefore(newer))
        XCTAssertTrue(sameTimeBiggerId.isOrderedBefore(older))
    }

    /// Кейс: патч по сообщению без отдельного превью.
    /// Ожидание: позиция — `createdAt` сообщения, превью собрано из самого сообщения.
    func test_patch_fromMessage_usesCreatedAtAndMessagePreview() {
        let message = Message.make(id: 20, conversationId: 3, text: "Ок", createdAt: .stub(500))

        let patch = ConversationPatch(message: message)

        XCTAssertEqual(patch.conversationId, 3)
        XCTAssertEqual(patch.positionUpdatedAt, .stub(500))
        XCTAssertEqual(patch.lastMessage, LastMessage(messageId: 20, type: .text, text: "Ок", updatedAt: .stub(500)))
    }
}
