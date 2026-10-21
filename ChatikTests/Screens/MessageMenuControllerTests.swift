//
//  MessageMenuControllerTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageMenuControllerTests: XCTestCase {
    private var presenter: MessageMenuPresenterMock!
    private var waits: [Gate] = []
    private var sut: MessageMenuController!
    private let message = MessageDisplayModel(
        id: MessageClientKey(senderId: 1, clientId: "a"),
        text: "Привет",
        isUnsupported: false,
        isOutgoing: true,
        sender: nil,
        time: "12:00",
        editedLabel: nil,
        deliveryState: .delivered,
        deliveryStateLabel: nil,
        actions: [.edit]
    )

    override func setUp() async throws {
        try await super.setUp()
        presenter = MessageMenuPresenterMock()
        waits = []
        sut = MessageMenuController(presenter: presenter) { [unowned self] _ in
            let gate = Gate()
            waits.append(gate)
            await gate.wait()
        }
    }

    override func tearDown() async throws {
        waits.forEach { $0.open() }
        sut = nil
        presenter = nil
        try await super.tearDown()
    }

    /// Кейс: клавиатуры нет; долгое нажатие на пузырь.
    /// Ожидание: клавиатура не трогается, меню показано сразу по текущему кадру пузыря, пузырь в ленте скрыт.
    func test_request_withoutKeyboard_presentsImmediately() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        var hideCount = 0

        sut.request(message: message, source: source, hideKeyboard: { hideCount += 1 }, onAction: { _ in })

        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(presenter.presented.map(\.frame), [source.screenFrame])
        XCTAssertEqual(sut.menuMessageId, message.id)
    }

    /// Кейс: клавиатура открыта; долгое нажатие, затем клавиатура спряталась, а пузырь за это время сдвинулся.
    /// Ожидание: клавиатура спрятана; до `keyboardDidHide` меню нет; после — показано по новому кадру пузыря.
    func test_request_withKeyboard_presentsAfterKeyboardHides() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        var hideCount = 0
        sut.keyboardWillShow()

        sut.request(message: message, source: source, hideKeyboard: { hideCount += 1 }, onAction: { _ in })
        XCTAssertEqual(hideCount, 1)
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertNil(sut.menuMessageId)
        source.screenFrame = CGRect(x: 100, y: 560, width: 200, height: 50)
        sut.keyboardDidHide()

        XCTAssertEqual(presenter.presented.map(\.frame), [CGRect(x: 100, y: 560, width: 200, height: 50)])
        XCTAssertEqual(sut.menuMessageId, message.id)
    }

    /// Кейс: клавиатура спряталась (`keyboardDidHide`), затем долгое нажатие.
    /// Ожидание: клавиатура не трогается, меню показано сразу.
    func test_request_afterKeyboardDidHide_presentsImmediately() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        var hideCount = 0
        sut.keyboardWillShow()
        sut.keyboardDidHide()

        sut.request(message: message, source: source, hideKeyboard: { hideCount += 1 }, onAction: { _ in })

        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(presenter.presented.count, 1)
    }

    /// Кейс: клавиатура открыта; долгое нажатие, а `keyboardDidHide` не пришло.
    /// Ожидание: по истечении ожидания меню всё равно показано, один раз.
    func test_request_keyboardDidHideMissing_presentsAfterWaitLimit() async {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        sut.keyboardWillShow()
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })
        await yieldUntil { [unowned self] in waits.first?.isWaiting == true }

        waits.first?.open()

        await yieldUntil { [unowned self] in presenter.presented.count == 1 }
        XCTAssertEqual(sut.menuMessageId, message.id)
    }

    /// Кейс: клавиатура спряталась и меню показано; затем истекло время ожидания.
    /// Ожидание: второго показа нет.
    func test_waitLimitAfterKeyboardDidHide_doesNotPresentTwice() async {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        sut.keyboardWillShow()
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })
        await yieldUntil { [unowned self] in waits.first?.isWaiting == true }
        sut.keyboardDidHide()

        waits.first?.open()
        await yieldTimes()

        XCTAssertEqual(presenter.presented.count, 1)
    }

    /// Кейс: меню открыто; ещё одно долгое нажатие.
    /// Ожидание: второе меню не показывается.
    func test_request_whileOpen_isIgnored() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })

        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })

        XCTAssertEqual(presenter.presented.count, 1)
    }

    /// Кейс: пузырь к моменту показа ушёл с экрана (кадра нет).
    /// Ожидание: меню не показано, пузырь не скрыт.
    func test_request_sourceOffscreen_doesNotPresent() {
        let source = MessageMenuSourceMock(screenFrame: nil)

        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertNil(sut.menuMessageId)
    }

    /// Кейс: презентер отказал в показе (окно прежнего меню ещё не убрано); затем долгое нажатие повторено.
    /// Ожидание: пузырь не скрыт после отказа, а повторное нажатие показывает меню.
    func test_request_presenterRefuses_keepsBubbleAndAcceptsNextRequest() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        presenter.isRefusing = true
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })
        XCTAssertNil(sut.menuMessageId)
        presenter.isRefusing = false

        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })

        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertEqual(sut.menuMessageId, message.id)
    }

    /// Кейс: меню открыто; лента пересобрана с тем же сообщением, с изменённым текстом, с изменённой пометкой
    /// «Изменено», с другими действиями (неотправленное снова отправляется) и без сообщения.
    /// Ожидание: меню закрывается без выбора во всех случаях, кроме неизменного сообщения.
    func test_feedDidChange_closesMenuOnlyWhenShownMessageChanged() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        let cases: [(messages: [MessageDisplayModel], dismisses: Bool)] = [
            ([message], false),
            ([message.with(text: "Привет всем")], true),
            ([message.with(editedLabel: "Изменено")], true),
            ([message.with(actions: [])], true),
            ([], true),
        ]

        for testCase in cases {
            let dismissesBefore = presenter.dismissCount
            sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })
            sut.feedDidChange([section(testCase.messages)])
            XCTAssertEqual(presenter.dismissCount - dismissesBefore, testCase.dismisses ? 1 : 0, "\(testCase.messages)")
            XCTAssertEqual(sut.menuMessageId == nil, testCase.dismisses)
            presenter.close(with: nil)
        }
    }

    /// Кейс: меню открыто у неотправленного сообщения; лента пересобрана, где оно снова отправляется.
    /// Ожидание: меню закрывается без выбора — «Повторить отправку» и «Удалить» уже недоступны.
    func test_feedDidChange_failedMessageStartsSending_closesMenu() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        let failed = outgoingMessage(status: .failed)
        sut.request(message: failed, source: source, hideKeyboard: {}, onAction: { _ in })

        sut.feedDidChange([section([outgoingMessage(status: .sending)])])

        XCTAssertEqual(presenter.dismissCount, 1)
        XCTAssertNil(sut.menuMessageId)
    }

    /// Кейс: меню закрыто выбором действия и, отдельно, без выбора.
    /// Ожидание: пузырь возвращается в обоих случаях; действие передаётся экрану только при выборе.
    func test_close_unhidesBubbleAndPassesAction() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 100, y: 300, width: 200, height: 50))
        var actions: [MessageAction] = []
        let closes: [MessageAction?] = [
            nil,
            .edit,
        ]

        for close in closes {
            sut.request(message: message, source: source, hideKeyboard: {}, onAction: { actions.append($0) })
            presenter.close(with: close)
            XCTAssertNil(sut.menuMessageId, String(describing: close))
        }

        XCTAssertEqual(actions, [.edit])
    }

    // MARK: - Helpers

    /// Своё сообщение очереди отправки в виде для ленты.
    /// - Parameter status: состояние отправки.
    private func outgoingMessage(status: OutgoingMessageStatus) -> MessageDisplayModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let context = MessageDisplayContext(
            currentUserId: 1,
            locale: Locale(identifier: "ru"),
            calendar: calendar,
            now: .distantPast,
            strings: .current,
            dateHeaderFormatter: RussianMessageDateHeaderFormatter(calendar: calendar)
        )
        return MessageDisplayModel(outgoing: .stub(clientId: "f", status: status), sender: nil, context: context)
    }

    /// Секция ленты с переданными сообщениями.
    /// - Parameter messages: сообщения секции.
    private func section(_ messages: [MessageDisplayModel]) -> MessageDaySectionDisplayModel {
        MessageDaySectionDisplayModel(id: MessageDaySectionID(day: .distantPast, occurrence: 0), title: "Сегодня", messages: messages)
    }

    /// Кейс: меню показано; экран уходит (`dismiss`).
    /// Ожидание: меню закрыто без выбора, пузырь в ленте снова виден.
    func test_dismiss_shownMenu_closesWithoutAction() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 0, y: 0, width: 100, height: 40))
        var actions: [MessageAction] = []
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { actions.append($0) })

        sut.dismiss()

        XCTAssertEqual(presenter.dismissCount, 1)
        XCTAssertNil(sut.menuMessageId)
        XCTAssertTrue(actions.isEmpty)
    }

    /// Кейс: клавиатура открыта, меню ждёт её скрытия; экран уходит (`dismiss`), затем клавиатура спряталась.
    /// Ожидание: ждущее меню не показывается.
    func test_dismiss_pendingMenu_isNotPresented() {
        let source = MessageMenuSourceMock(screenFrame: CGRect(x: 0, y: 0, width: 100, height: 40))
        sut.keyboardWillShow()
        sut.request(message: message, source: source, hideKeyboard: {}, onAction: { _ in })

        sut.dismiss()
        sut.keyboardDidHide()

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertNil(sut.menuMessageId)
    }
}

private extension MessageDisplayModel {
    /// Копия с другим текстом, пометкой «Изменено» или действиями.
    /// - Parameters:
    ///   - text: новый текст; `nil` — прежний.
    ///   - editedLabel: новая пометка; `nil` — прежняя.
    ///   - actions: новые действия; `nil` — прежние.
    func with(text: String? = nil, editedLabel: String? = nil, actions: [MessageAction]? = nil) -> MessageDisplayModel {
        MessageDisplayModel(
            id: id,
            text: text ?? self.text,
            isUnsupported: isUnsupported,
            isOutgoing: isOutgoing,
            sender: sender,
            time: time,
            editedLabel: editedLabel ?? self.editedLabel,
            deliveryState: deliveryState,
            deliveryStateLabel: deliveryStateLabel,
            actions: actions ?? self.actions
        )
    }
}
