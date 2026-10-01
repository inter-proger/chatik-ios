//
//  APIResponseTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class APIResponseTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: успешный ответ с action `users` из документации.
    /// Ожидание: `response` разобран, action прочитан с id пользователей.
    func test_decode_usersAction_readsUserIds() throws {
        let json = #"{"status":1,"response":{},"actions":[{"type":"users","data":{"userIds":[1,2]}}]}"#

        let response = try decode(json)

        XCTAssertEqual(response.response, EmptyResponse())
        XCTAssertEqual(response.actions, [.users(userIds: [1, 2])])
    }

    /// Кейс: поля `actions` нет — сервер не присылает его, если указаний нет, и в ответах с ошибкой.
    /// Ожидание: список actions пуст, разбор не падает.
    func test_decode_withoutActions_hasEmptyActions() throws {
        let responses = [
            #"{"status":1,"response":{}}"#,
            #"{"status":0,"errorCode":2003}"#,
        ]

        for json in responses {
            XCTAssertEqual(try decode(json).actions, [], json)
        }
    }

    /// Кейс: среди actions есть неизвестный клиенту тип и action `users` с битыми данными.
    /// Ожидание: оба пропущены, известный корректный action прочитан, ответ разобран — ошибкой это не считается.
    func test_decode_unknownAndMalformedActions_areSkipped() throws {
        let json = """
        {
          "status": 1,
          "response": {},
          "actions": [
            { "type": "typing", "data": { "conversationId": 1 } },
            { "type": "users", "data": { "userIds": "1,2" } },
            { "data": {} },
            { "type": "users", "data": { "userIds": [3] } }
          ]
        }
        """

        let response = try decode(json)

        XCTAssertEqual(response.actions, [.users(userIds: [3])])
    }

    /// Кейс: `actions` пришёл не массивом.
    /// Ожидание: данные метода разобраны, actions пусты — указания не важнее данных.
    func test_decode_actionsNotArray_keepsResponse() throws {
        let json = #"{"status":1,"response":{},"actions":{"type":"users"}}"#

        let response = try decode(json)

        XCTAssertEqual(response.response, EmptyResponse())
        XCTAssertEqual(response.actions, [])
    }

    /// Разбирает обёртку ответа с пустыми данными метода.
    /// - Parameter json: тело ответа.
    private func decode(_ json: String) throws -> APIResponse<EmptyResponse> {
        try decoder.decode(APIResponse<EmptyResponse>.self, from: Data(json.utf8))
    }
}
