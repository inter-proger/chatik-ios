//
//  UserTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UserTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: профиль без аватара (`"avatar": null`).
    /// Ожидание: поля разобраны, `avatar == nil`.
    func test_decode_nullAvatar_returnsUserWithoutAvatar() throws {
        let json = #"{"userId":1,"login":"ivan","name":"Ivan Petrov","avatar":null}"#

        let user = try decoder.decode(User.self, from: Data(json.utf8))

        XCTAssertEqual(user, User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil))
    }

    /// Кейс: профиль с аватаром-изображением.
    /// Ожидание: `avatar` разобран как `RemoteFile` типа `image` с уменьшенной копией.
    func test_decode_withAvatar_returnsUserWithImageFile() throws {
        let json = """
        {
          "userId": 1, "login": "ivan", "name": "Ivan",
          "avatar": {
            "fileId": 5, "type": "image", "url": "http://h/a.jpg", "size": 1, "filename": "a.jpg", "extension": "jpg",
            "data": { "smallUrl": "http://h/a_small.jpg" }
          }
        }
        """

        let user = try decoder.decode(User.self, from: Data(json.utf8))

        XCTAssertEqual(user.avatar?.fileId, 5)
        XCTAssertEqual(user.avatar?.type, .image)
        XCTAssertEqual(user.avatar?.smallURL, URL(string: "http://h/a_small.jpg"))
    }

    /// Кейс: пользователь с аватаром закодирован и декодирован обратно (так он хранится в `UserDefaults`).
    /// Ожидание: значение восстановлено без потерь, `smallUrl` записан внутри вложенного `data`.
    func test_codable_roundTrip_preservesUserWithAvatar() throws {
        let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub)

        let data = try JSONEncoder().encode(user)
        let decoded = try decoder.decode(User.self, from: data)

        XCTAssertEqual(decoded, user)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let avatarData = (json["avatar"] as? [String: Any])?["data"] as? [String: Any]
        XCTAssertEqual(avatarData?["smallUrl"] as? String, RemoteFile.stub.smallURL?.absoluteString)
    }
}
