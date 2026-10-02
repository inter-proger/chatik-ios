//
//  ChatRowDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatRowDisplayModelTests: XCTestCase {
    /// Кейс: личная переписка, собеседник загружен в кэш.
    /// Ожидание: заголовок строки — имя собеседника, аватар — его аватар (уменьшенная копия), без заглушки.
    func test_init_singleWithLoadedOpponent_usesOpponentNameAndAvatar() {
        let opponent = User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: .stub)

        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .loaded(opponent))

        XCTAssertEqual(model.id, Conversation.singleStub.id)
        XCTAssertEqual(model.title, "Petr Sidorov")
        XCTAssertFalse(model.isTitlePlaceholder)
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: личная переписка, собеседник ещё загружается.
    /// Ожидание: заголовок — заглушка, аватара нет.
    func test_init_singleWithPendingOpponent_showsPlaceholder() {
        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .pending)

        XCTAssertEqual(model.title, ChatListStrings.rowLoading)
        XCTAssertTrue(model.isTitlePlaceholder)
        XCTAssertNil(model.avatarURL)
    }

    /// Кейс: личная переписка, собеседника нет на сервере.
    /// Ожидание: заголовок — текст об удалённом пользователе, не заглушка.
    func test_init_singleWithMissingOpponent_showsDeletedUser() {
        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .notFound)

        XCTAssertEqual(model.title, ChatListStrings.rowDeletedUser)
        XCTAssertFalse(model.isTitlePlaceholder)
    }

    /// Кейс: групповая переписка — с названием и аватаром, без собеседника.
    /// Ожидание: заголовок строки — название группы, аватар — её аватар (уменьшенная копия).
    func test_init_group_usesNameAndAvatar() {
        let model = ChatRowDisplayModel(conversation: .groupStub, opponent: nil)

        XCTAssertEqual(model.id, Conversation.groupStub.id)
        XCTAssertEqual(model.title, Conversation.groupStub.name)
        XCTAssertFalse(model.isTitlePlaceholder)
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: у переписки нет ни названия, ни собеседника — например, тип неизвестен клиенту.
    /// Ожидание: заголовок — запасной текст, строка не выглядит пустой.
    func test_init_withoutNameAndOpponent_usesUntitledTitle() {
        let conversation = Conversation(conversationId: 1, type: .unknown, memberIds: [1, 2], name: nil, avatar: nil, opponentUserId: nil, updatedAt: Date(timeIntervalSince1970: 1_790_846_400))

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation, opponent: nil).title, ChatListStrings.rowUntitled)
    }

    /// Кейс: у аватара нет уменьшенной копии.
    /// Ожидание: для строки берётся полноразмерный URL.
    func test_init_withoutSmallCopy_usesFullURL() {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        let conversation = Conversation(conversationId: 1, type: .group, memberIds: [1, 2], name: "Группа", avatar: avatar, opponentUserId: nil, updatedAt: Date(timeIntervalSince1970: 1_790_846_400))

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation, opponent: nil).avatarURL, RemoteFile.stub.url)
    }
}
