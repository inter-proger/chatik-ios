//
//  ConversationTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: личная переписка из документации — без названия и аватара, с собеседником.
    /// Ожидание: поля разобраны, `type == .single`, `name` и `avatar` — `nil`, собеседник прочитан как `User`.
    func test_decode_single_readsMembersAndOpponentWithoutNameAndAvatar() throws {
        let json = """
        {
          "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
          "opponentUser": { "userId": 2, "login": "petr", "name": "Petr Sidorov", "avatar": null }
        }
        """

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.conversationId, 1)
        XCTAssertEqual(conversation.type, .single)
        XCTAssertEqual(conversation.memberIds, [1, 2])
        XCTAssertNil(conversation.name)
        XCTAssertNil(conversation.avatar)
        XCTAssertEqual(conversation.opponentUser, User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))
    }

    /// Кейс: групповая переписка с названием и аватаром-изображением.
    /// Ожидание: `type == .group`, название прочитано, аватар разобран как `RemoteFile`.
    func test_decode_group_readsNameAndAvatar() throws {
        let json = """
        {
          "conversationId": 7, "type": "group", "memberIds": [1, 2, 3], "name": "Команда", "opponentUser": null,
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
        XCTAssertNil(conversation.opponentUser)
    }

    /// Кейс: переписка используется как элемент списка.
    /// Ожидание: `id` совпадает с `conversationId`.
    func test_id_matchesConversationId() throws {
        let json = #"{"conversationId":42,"type":"single","memberIds":[1,2],"name":null,"avatar":null,"opponentUser":null}"#

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.id, 42)
    }

    /// Кейс: сервер прислал тип переписки, которого клиент ещё не знает.
    /// Ожидание: тип читается как `.unknown`, остальные поля разобраны — новый тип не ломает разбор списка.
    func test_decode_unknownType_fallsBackToUnknown() throws {
        let json = #"{"conversationId":9,"type":"channel","memberIds":[1,2],"name":"Канал","avatar":null,"opponentUser":null}"#

        let conversation = try decoder.decode(Conversation.self, from: Data(json.utf8))

        XCTAssertEqual(conversation.type, .unknown)
        XCTAssertEqual(conversation.conversationId, 9)
        XCTAssertEqual(conversation.name, "Канал")
    }

    /// Кейс: в JSON нет обязательного поля `memberIds`.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingRequiredField_throws() {
        let json = #"{"conversationId":1,"type":"single","name":null,"avatar":null,"opponentUser":null}"#

        XCTAssertThrowsError(try decoder.decode(Conversation.self, from: Data(json.utf8)))
    }
}
