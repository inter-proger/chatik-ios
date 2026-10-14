//
//  ChatRowDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatRowDisplayModelTests: XCTestCase {
    private let timeFormatter = MessageTimeFormatter(
        locale: Locale(identifier: "ru_RU"),
        calendar: ChatRowDisplayModelTests.utcCalendar,
        now: ServerTime.stub.date
    )

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Кейс: личная переписка, собеседник загружен в кэш.
    /// Ожидание: заголовок строки — имя собеседника, аватар — его аватар (уменьшенная копия), без заглушки.
    func test_init_singleWithLoadedOpponent_usesOpponentNameAndAvatar() {
        let opponent = User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: .stub)

        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .loaded(opponent), timeFormatter: timeFormatter)

        XCTAssertEqual(model.id, Conversation.singleStub.id)
        XCTAssertEqual(model.title, "Petr Sidorov")
        XCTAssertFalse(model.isTitlePlaceholder)
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: личная переписка, собеседник ещё загружается.
    /// Ожидание: заголовок — заглушка, аватара нет.
    func test_init_singleWithPendingOpponent_showsPlaceholder() {
        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .pending, timeFormatter: timeFormatter)

        XCTAssertEqual(model.title, ChatListStrings.rowLoading)
        XCTAssertTrue(model.isTitlePlaceholder)
        XCTAssertNil(model.avatarURL)
    }

    /// Кейс: личная переписка, собеседника нет на сервере.
    /// Ожидание: заголовок — текст об удалённом пользователе, не заглушка.
    func test_init_singleWithMissingOpponent_showsDeletedUser() {
        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: .notFound, timeFormatter: timeFormatter)

        XCTAssertEqual(model.title, ChatListStrings.rowDeletedUser)
        XCTAssertFalse(model.isTitlePlaceholder)
    }

    /// Кейс: групповая переписка — с названием и аватаром, без собеседника.
    /// Ожидание: заголовок строки — название группы, аватар — её аватар (уменьшенная копия).
    func test_init_group_usesNameAndAvatar() {
        let model = ChatRowDisplayModel(conversation: .groupStub, opponent: nil, timeFormatter: timeFormatter)

        XCTAssertEqual(model.id, Conversation.groupStub.id)
        XCTAssertEqual(model.title, Conversation.groupStub.name)
        XCTAssertFalse(model.isTitlePlaceholder)
        XCTAssertEqual(model.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: у переписки нет ни названия, ни собеседника — например, тип неизвестен клиенту.
    /// Ожидание: заголовок — запасной текст, строка не выглядит пустой.
    func test_init_withoutNameAndOpponent_usesUntitledTitle() {
        let conversation = Conversation(
            conversationId: 1, type: .unknown, memberIds: [1, 2], name: nil, avatar: nil, opponentUserId: nil,
            lastMessage: nil, positionUpdatedAt: .stub, updatedInfoAt: .stub
        )

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation, opponent: nil, timeFormatter: timeFormatter).title, ChatListStrings.rowUntitled)
    }

    /// Кейс: у аватара нет уменьшенной копии.
    /// Ожидание: для строки берётся полноразмерный URL.
    func test_init_withoutSmallCopy_usesFullURL() {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        let conversation = Conversation(
            conversationId: 1, type: .group, memberIds: [1, 2], name: "Группа", avatar: avatar, opponentUserId: nil,
            lastMessage: nil, positionUpdatedAt: .stub, updatedInfoAt: .stub
        )

        XCTAssertEqual(ChatRowDisplayModel(conversation: conversation, opponent: nil, timeFormatter: timeFormatter).avatarURL, RemoteFile.stub.url)
    }

    // MARK: - Превью и время

    /// Кейс: последнее сообщение — текст.
    /// Ожидание: превью — текст сообщения.
    func test_init_textLastMessage_previewIsText() {
        let model = ChatRowDisplayModel(conversation: .groupStub, opponent: nil, timeFormatter: timeFormatter)

        XCTAssertEqual(model.preview, "Привет!")
    }

    /// Кейс: в переписке нет сообщений.
    /// Ожидание: превью пустое.
    func test_init_withoutLastMessage_previewIsEmpty() {
        let model = ChatRowDisplayModel(conversation: .singleStub, opponent: nil, timeFormatter: timeFormatter)

        XCTAssertEqual(model.preview, "")
    }

    /// Кейс: последнее сообщение неизвестного типа либо без текста.
    /// Ожидание: превью — «Сообщение».
    func test_init_lastMessageWithoutDisplayableText_previewIsPlaceholder() {
        let lastMessages = [
            LastMessage(messageId: 1, type: .unknown, text: "что-то", updatedAt: .stub),
            LastMessage(messageId: 2, type: .text, text: nil, updatedAt: .stub),
        ]

        for lastMessage in lastMessages {
            let conversation = Conversation.singleStub.with(position: .stub, lastMessage: lastMessage)
            let model = ChatRowDisplayModel(conversation: conversation, opponent: nil, timeFormatter: timeFormatter)
            XCTAssertEqual(model.preview, ChatListStrings.rowMessage, "\(lastMessage)")
        }
    }

    /// Кейс: переписка поднялась сегодня и в прошлом году.
    /// Ожидание: время — в формате ленты: сегодня только время, раньше — с датой и годом.
    func test_init_time_usesFeedFormat() {
        let today = Conversation.singleStub.with(position: .stub, lastMessage: nil)
        let lastYear = Conversation.singleStub.with(position: .stub(-400 * 86_400_000), lastMessage: nil)

        let todayTime = ChatRowDisplayModel(conversation: today, opponent: nil, timeFormatter: timeFormatter).time
        let lastYearTime = ChatRowDisplayModel(conversation: lastYear, opponent: nil, timeFormatter: timeFormatter).time

        XCTAssertEqual(todayTime, timeFormatter.string(from: ServerTime.stub.date))
        XCTAssertEqual(todayTime, "09:20")
        XCTAssertTrue(lastYearTime.contains("2025"), lastYearTime)
    }
}
