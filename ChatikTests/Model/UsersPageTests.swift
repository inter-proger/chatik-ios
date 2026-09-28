//
//  UsersPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UsersPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: страница из документации с двумя пользователями.
    /// Ожидание: пользователи разобраны в порядке ответа, `nextMaxId` — из ответа.
    func test_decode_readsUsersAndNextMaxId() throws {
        let json = """
        {
          "users": [
            { "userId": 1, "login": "ivan", "name": "Ivan Petrov", "avatar": null },
            { "userId": 5, "login": "ivanova", "name": "Anna Ivanova", "avatar": null }
          ],
          "nextMaxId": 5
        }
        """

        let page = try decoder.decode(UsersPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.users.map(\.userId), [1, 5])
        XCTAssertEqual(page.users.first?.login, "ivan")
        XCTAssertEqual(page.nextMaxId, 5)
    }

    /// Кейс: пустая страница — пользователей по фильтру нет.
    /// Ожидание: пустой список и `nextMaxId == nil`.
    func test_decode_emptyPage_hasNoNextMaxId() throws {
        let json = #"{"users":[],"nextMaxId":null}"#

        let page = try decoder.decode(UsersPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.users.isEmpty)
        XCTAssertNil(page.nextMaxId)
    }
}
