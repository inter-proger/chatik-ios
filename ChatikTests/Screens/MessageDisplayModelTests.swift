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

    /// Кейс: сообщения сегодняшнего, позавчерашнего и прошлогоднего дня, отправленные в 10:00.
    /// Ожидание: в пузыре у всех только время — дату показывает заголовок дня.
    func test_formattedTime_anyDay_showsTimeOnly() {
        let dates = [
            now.addingTimeInterval(-2 * 3600),
            now.addingTimeInterval(-2 * 86_400 - 2 * 3600),
            now.addingTimeInterval(-365 * 86_400 - 2 * 3600),
        ]

        for date in dates {
            XCTAssertEqual(MessageDisplayModel.formattedTime(date, context: makeContext()), "10:00", "\(date)")
        }
    }

    /// Кейс: сообщение с сервера.
    /// Ожидание: время отправки на сервере есть.
    func test_init_serverMessage_hasTime() {
        let sut = MessageDisplayModel(message: .make(id: 1, createdAt: ServerTime(milliseconds: Int64(now.timeIntervalSince1970) * 1000)), sender: nil, context: makeContext())

        XCTAssertEqual(sut.time, "12:00")
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
        let message = Message(messageId: 1, clientId: "a", conversationId: 1, blockId: 1, senderId: 2, type: .unknown, text: "", isEdited: false, createdAt: .stub, updatedAt: .stub)

        let sut = MessageDisplayModel(message: message, sender: nil, context: makeContext())

        XCTAssertTrue(sut.isUnsupported)
        XCTAssertEqual(sut.text, ChatStrings.messageUnsupported)
    }

    // MARK: - Состояние доставки

    /// Кейс: сообщение с сервера.
    /// Ожидание: доставлено, без описания состояния; идентификатор — отправитель и `clientId`.
    func test_init_serverMessage_isDelivered() {
        let sut = MessageDisplayModel(message: .stub, sender: nil, context: makeContext())

        XCTAssertEqual(sut.deliveryState, .delivered)
        XCTAssertNil(sut.deliveryStateLabel)
        XCTAssertEqual(sut.id, Message.stub.clientKey)
    }

    /// Кейс: неотправленное сообщение в статусах «отправляется» и «не отправлено».
    /// Ожидание: исходящее, состояние и его описание соответствуют статусу; времени нет — на его месте состояние.
    func test_init_outgoing_mapsStatus() {
        let cases: [(status: OutgoingMessageStatus, state: MessageDeliveryState, label: String)] = [
            (.sending, .sending, ChatStrings.messageSending),
            (.failed, .failed, ChatStrings.messageFailed),
        ]

        for testCase in cases {
            let outgoing = OutgoingMessage.stub(clientId: "a", createdAt: now, status: testCase.status)
            let sut = MessageDisplayModel(outgoing: outgoing, sender: nil, context: makeContext())
            XCTAssertTrue(sut.isOutgoing)
            XCTAssertEqual(sut.deliveryState, testCase.state)
            XCTAssertEqual(sut.deliveryStateLabel, testCase.label)
            XCTAssertNil(sut.time)
            XCTAssertEqual(sut.id, outgoing.clientKey)
        }
    }

    // MARK: - Отправитель

    /// Кейс: первое сообщение серии при разных состояниях отправителя в кэше.
    /// Ожидание: загруженный — его имя и уменьшенная копия аватара, загружается — заглушка без аватара,
    /// удалён — текст об удалённом пользователе без аватара.
    func test_init_firstInSeries_senderByCacheState() {
        let avatar = RemoteFile.stub
        let cases: [(sender: CachedUser, expected: MessageSenderDisplayModel)] = [
            (.loaded(User(userId: 2, login: "petr", name: "Petr", avatar: avatar)), MessageSenderDisplayModel(name: "Petr", isPlaceholder: false, avatarURL: avatar.smallURL)),
            (.pending, MessageSenderDisplayModel(name: ChatStrings.userLoading, isPlaceholder: true, avatarURL: nil)),
            (.notFound, MessageSenderDisplayModel(name: ChatStrings.userDeleted, isPlaceholder: false, avatarURL: nil)),
        ]

        for testCase in cases {
            let sut = MessageDisplayModel(message: .make(id: 1, senderId: 2), sender: testCase.sender, context: makeContext())
            XCTAssertEqual(sut.sender, testCase.expected)
        }
    }

    /// Кейс: исходящее сообщение — первое в серии.
    /// Ожидание: имя и аватар отправителя показываются и у своего сообщения.
    func test_init_outgoingFirstInSeries_showsSender() {
        let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)

        let sut = MessageDisplayModel(message: .make(id: 1, senderId: 1), sender: .loaded(user), context: makeContext())

        XCTAssertTrue(sut.isOutgoing)
        XCTAssertEqual(sut.sender?.name, "Ivan")
    }

    /// Кейс: сообщение продолжает серию — отправитель не передан.
    /// Ожидание: ни имени, ни аватара.
    func test_init_continuesSeries_hasNoSender() {
        let sut = MessageDisplayModel(message: .make(id: 1, senderId: 2), sender: nil, context: makeContext())

        XCTAssertNil(sut.sender)
    }

    // MARK: - Helpers

    /// Контекст отображения с русской локалью и часовым поясом UTC.
    /// - Parameter currentUserId: текущий пользователь.
    private func makeContext(currentUserId: Int? = 1) -> MessageDisplayContext {
        MessageDisplayContext(
            currentUserId: currentUserId,
            locale: Locale(identifier: "ru"),
            calendar: calendar,
            now: now,
            strings: .current,
            dateHeaderFormatter: RussianMessageDateHeaderFormatter(calendar: calendar)
        )
    }
}
