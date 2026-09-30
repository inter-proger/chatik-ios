//
//  ChatRowDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatRowDisplayModelTests: XCTestCase {
    /// Кейс: личная переписка — заголовка (`name`) у неё нет.
    /// Ожидание: заголовок строки — имя собеседника, аватар — его аватар.
    func test_init_single_usesOpponentNameAndAvatar() {
        let model = ChatRowDisplayModel(conversation: .singleStub)

        XCTAssertEqual(model.id, Conversation.singleStub.id)
        XCTAssertEqual(model.title, Conversation.singleStub.opponentUser?.name)
        XCTAssertNil(model.avatarURL)
    }

    /// Кейс: групповая переписка — с названием и аватаром.
    /// Ожидание: заголовок строки — название группы, аватар — её аватар (уменьшенная копия).
    func test_init_group_usesNameAndAvatar() {
        let model = ChatRowDisplayModel(conversation: .groupStub)

        XCTAssertEqual(model.id, Conversation.groupStub.id)
        XCTAssertEqual(model.title, Conversation.groupStub.name)
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: у переписки нет ни названия, ни собеседника — например, тип неизвестен клиенту.
    /// Ожидание: заголовок — запасной текст, строка не выглядит пустой.
    func test_init_withoutNameAndOpponent_usesUntitledTitle() {
        let conversation = Conversation(conversationId: 1, type: .unknown, memberIds: [1, 2], name: nil, avatar: nil, opponentUser: nil)

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation).title, ChatListStrings.rowUntitled)
    }

    /// Кейс: у аватара нет уменьшенной копии.
    /// Ожидание: для строки берётся полноразмерный URL.
    func test_init_withoutSmallCopy_usesFullURL() {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        let conversation = Conversation(conversationId: 1, type: .group, memberIds: [1, 2], name: "Группа", avatar: avatar, opponentUser: nil)

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation).avatarURL, RemoteFile.stub.url)
    }
}
