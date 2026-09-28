//
//  UserRowDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UserRowDisplayModelTests: XCTestCase {
    /// Кейс: пользователь без аватара.
    /// Ожидание: имя как есть, логин с префиксом `@`, URL аватара `nil`.
    func test_init_withoutAvatar() {
        let model = UserRowDisplayModel(user: .stub)

        XCTAssertEqual(model.id, User.stub.userId)
        XCTAssertEqual(model.name, User.stub.name)
        XCTAssertEqual(model.login, "@\(User.stub.login)")
        XCTAssertNil(model.avatarURL)
    }

    /// Кейс: у аватара есть уменьшенная копия.
    /// Ожидание: для списка берётся уменьшенная копия.
    func test_init_withSmallCopy_usesSmallURL() {
        let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub)

        XCTAssertEqual(UserRowDisplayModel(user: user).avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: у аватара нет уменьшенной копии.
    /// Ожидание: берётся полноразмерный URL.
    func test_init_withoutSmallCopy_usesFullURL() {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: avatar)

        XCTAssertEqual(UserRowDisplayModel(user: user).avatarURL, RemoteFile.stub.url)
    }
}
