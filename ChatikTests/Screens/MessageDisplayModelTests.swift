//
//  MessageDisplayModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageDisplayModelTests: XCTestCase {
    /// 2026-09-30 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_769_600)
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Время

    /// Кейс: сообщение отправлено сегодня.
    /// Ожидание: показано только время.
    func test_formattedTime_today_showsTimeOnly() {
        let date = now.addingTimeInterval(-2 * 3600)

        let time = MessageDisplayModel.formattedTime(date, context: makeContext())

        XCTAssertEqual(time, "10:00")
    }

    /// Кейс: сообщение отправлено в другой день этого года.
    /// Ожидание: показаны день, месяц и время, без года.
    func test_formattedTime_earlierThisYear_showsDayAndTime() {
        let date = now.addingTimeInterval(-3 * 86_400)

        let time = MessageDisplayModel.formattedTime(date, context: makeContext())

        XCTAssertTrue(time.contains("27"), time)
        XCTAssertTrue(time.contains("12:00"), time)
        XCTAssertFalse(time.contains("2026"), time)
    }

    /// Кейс: сообщение отправлено в прошлом году.
    /// Ожидание: показан и год.
    func test_formattedTime_previousYear_showsYear() {
        let date = now.addingTimeInterval(-365 * 86_400)

        let time = MessageDisplayModel.formattedTime(date, context: makeContext())

        XCTAssertTrue(time.contains("2025"), time)
    }

    // MARK: - Содержимое

    /// Кейс: отредактированное сообщение текущего пользователя.
    /// Ожидание: исходящее, с пометкой «изменено» и исходным текстом.
    func test_init_ownEditedMessage_isOutgoingWithEditedLabel() {
        let sut = MessageDisplayModel(message: .editedStub, sender: nil, context: makeContext(currentUserId: Message.editedStub.senderId))

        XCTAssertTrue(sut.isOutgoing)
        XCTAssertEqual(sut.text, Message.editedStub.text)
        XCTAssertEqual(sut.editedLabel, ChatStrings.messageEdited)
    }

    /// Кейс: сообщение типа, который клиент не знает.
    /// Ожидание: вместо текста — пояснение, что сообщение не поддерживается.
    func test_init_unknownType_showsUnsupportedText() {
        let message = Message(messageId: 1, conversationId: 1, blockId: 1, senderId: 2, type: .unknown, text: "", isEdited: false, createdAt: now, updatedAt: now)

        let sut = MessageDisplayModel(message: message, sender: nil, context: makeContext())

        XCTAssertTrue(sut.isUnsupported)
        XCTAssertEqual(sut.text, ChatStrings.messageUnsupported)
    }

    // MARK: - Отправитель

    /// Кейс: входящее сообщение групповой переписки при разных состояниях отправителя в кэше.
    /// Ожидание: загруженный — его имя, загружается — заглушка, удалён — текст об удалённом пользователе.
    func test_init_groupIncoming_senderNameByCacheState() {
        let cases: [(sender: CachedUser, name: String, isPlaceholder: Bool)] = [
            (.loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil)), "Petr", false),
            (.pending, ChatStrings.userLoading, true),
            (.notFound, ChatStrings.userDeleted, false),
        ]

        for testCase in cases {
            let sut = MessageDisplayModel(message: .make(id: 1, senderId: 2), sender: testCase.sender, context: makeContext(showsSenderNames: true))
            XCTAssertEqual(sut.senderName, testCase.name)
            XCTAssertEqual(sut.isSenderPlaceholder, testCase.isPlaceholder)
        }
    }

    /// Кейс: исходящее сообщение групповой переписки.
    /// Ожидание: имя отправителя не показывается.
    func test_init_groupOutgoing_hidesSenderName() {
        let sut = MessageDisplayModel(message: .make(id: 1, senderId: 1), sender: .pending, context: makeContext(showsSenderNames: true))

        XCTAssertNil(sut.senderName)
        XCTAssertFalse(sut.isSenderPlaceholder)
    }

    // MARK: - Helpers

    /// Контекст отображения с русской локалью и часовым поясом UTC.
    /// - Parameters:
    ///   - currentUserId: текущий пользователь.
    ///   - showsSenderNames: показывать ли имена отправителей.
    private func makeContext(currentUserId: Int? = 1, showsSenderNames: Bool = false) -> MessageDisplayContext {
        MessageDisplayContext(
            currentUserId: currentUserId,
            showsSenderNames: showsSenderNames,
            locale: Locale(identifier: "ru"),
            calendar: calendar,
            now: now
        )
    }
}
