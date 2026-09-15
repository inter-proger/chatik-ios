//
//  UserTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UserTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: профиль без аватара (`"avatar": null`).
    /// Ожидание: поля в snake_case разобраны, `avatar == nil`.
    func test_decode_nullAvatar_returnsUserWithoutAvatar() throws {
        let json = #"{"user_id":1,"login":"ivan","name":"Ivan Petrov","avatar":null}"#

        let user = try decoder.decode(User.self, from: Data(json.utf8))

        XCTAssertEqual(user, User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil))
    }

    /// Кейс: профиль с аватаром-изображением.
    /// Ожидание: `avatar` разобран как `RemoteFile` типа `image` с уменьшенной копией.
    func test_decode_withAvatar_returnsUserWithImageFile() throws {
        let json = """
        {
          "user_id": 1, "login": "ivan", "name": "Ivan",
          "avatar": {
            "file_id": 5, "type": "image", "url": "http://h/a.jpg", "size": 1, "filename": "a.jpg", "extension": "jpg",
            "data": { "small_url": "http://h/a_small.jpg" }
          }
        }
        """

        let user = try decoder.decode(User.self, from: Data(json.utf8))

        XCTAssertEqual(user.avatar?.fileId, 5)
        XCTAssertEqual(user.avatar?.type, .image)
        XCTAssertEqual(user.avatar?.smallURL, URL(string: "http://h/a_small.jpg"))
    }
}
