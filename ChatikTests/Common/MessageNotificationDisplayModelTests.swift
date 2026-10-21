//
//  MessageNotificationDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageNotificationDisplayModelTests: XCTestCase {
    private let sender = User(userId: 2, login: "anna", name: "Anna", avatar: .stub)

    /// Кейс: сообщение в личной переписке, отправитель загружен.
    /// Ожидание: заголовок — имя отправителя, аватар — его уменьшенная копия, текст без префикса.
    func test_init_single_usesSenderNameWithoutPrefix() {
        let message = Message.make(id: 7, conversationId: 1, senderId: 2, text: "Привет")

        let model = MessageNotificationDisplayModel(message: message, conversation: .singleStub, sender: .loaded(sender))

        XCTAssertEqual(model.conversationId, 1)
        XCTAssertEqual(model.messageId, 7)
        XCTAssertEqual(model.title, "Anna")
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
        XCTAssertEqual(String(model.text.characters), "Привет")
    }

    /// Кейс: сообщение в группе с названием.
    /// Ожидание: заголовок — название группы, текст с префиксом «Имя:», аватар — отправителя, а не группы.
    func test_init_group_usesGroupNameAndSenderPrefix() {
        let message = Message.make(id: 7, conversationId: 2, senderId: 2, text: "Созвон в 15:00")
        let senderWithoutAvatar = User(userId: 2, login: "anna", name: "Anna", avatar: nil)

        let model = MessageNotificationDisplayModel(message: message, conversation: .groupStub, sender: .loaded(senderWithoutAvatar))

        XCTAssertEqual(model.title, "Команда")
        XCTAssertEqual(String(model.text.characters), "Anna: Созвон в 15:00")
        XCTAssertNil(model.avatarURL)
    }

    /// Кейс: группа без названия.
    /// Ожидание: запасной заголовок.
    func test_init_groupWithoutName_usesUntitled() {
        let conversation = Conversation.groupStub.with(name: nil, updatedInfoAt: .stub)

        let model = MessageNotificationDisplayModel(message: .make(id: 1, conversationId: 2, senderId: 2), conversation: conversation, sender: .loaded(sender))

        XCTAssertEqual(model.title, InAppNotificationStrings.messageUntitled)
    }

    /// Кейс: отправитель не загрузился (`.pending`) или его нет на сервере (`.notFound`) — в личной переписке и в группе.
    /// Ожидание: вместо имени заглушка или «Удалённый пользователь», аватара нет.
    func test_init_unloadedSender_usesPlaceholderName() {
        let cases: [(sender: CachedUser, name: String)] = [
            (.pending, InAppNotificationStrings.messageUnknownSender),
            (.notFound, InAppNotificationStrings.messageDeletedSender),
        ]

        for (sender, name) in cases {
            let single = MessageNotificationDisplayModel(message: .make(id: 1, senderId: 2, text: "Привет"), conversation: .singleStub, sender: sender)
            let group = MessageNotificationDisplayModel(message: .make(id: 1, conversationId: 2, senderId: 2, text: "Привет"), conversation: .groupStub, sender: sender)

            XCTAssertEqual(single.title, name)
            XCTAssertNil(single.avatarURL)
            XCTAssertEqual(String(group.text.characters), "\(name): Привет")
        }
    }

    /// Кейс: у аватара отправителя нет уменьшенной копии.
    /// Ожидание: берётся полноразмерный URL.
    func test_init_avatarWithoutSmallCopy_usesFullURL() {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        let sender = User(userId: 2, login: "anna", name: "Anna", avatar: avatar)

        let model = MessageNotificationDisplayModel(message: .make(id: 1, senderId: 2), conversation: .singleStub, sender: .loaded(sender))

        XCTAssertEqual(model.avatarURL, RemoteFile.stub.url)
    }

    /// Кейс: многострочный текст с пробелами по краям.
    /// Ожидание: текст в одну строку.
    func test_init_multilineText_isSingleLine() {
        let message = Message.make(id: 1, senderId: 2, text: "  Первая\n\nвторая  ")

        let model = MessageNotificationDisplayModel(message: message, conversation: .singleStub, sender: .loaded(sender))

        XCTAssertEqual(String(model.text.characters), "Первая вторая")
    }

    /// Кейс: сообщение неизвестного типа.
    /// Ожидание: вместо текста — «Сообщение».
    func test_init_unknownType_usesUnsupportedText() {
        let stub = Message.make(id: 1, senderId: 2)
        let message = Message(
            messageId: stub.messageId, clientId: stub.clientId, conversationId: stub.conversationId, blockId: stub.blockId,
            senderId: stub.senderId, type: .unknown, text: "", isEdited: false, createdAt: stub.createdAt, updatedAt: stub.updatedAt
        )

        let model = MessageNotificationDisplayModel(message: message, conversation: .singleStub, sender: .loaded(sender))

        XCTAssertEqual(String(model.text.characters), InAppNotificationStrings.messageUnsupported)
    }
}
