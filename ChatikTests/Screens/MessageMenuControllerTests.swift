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
        sut.keyboardWillHide()
        source.screenFrame = CGRect(x: 100, y: 560, width: 200, height: 50)
        sut.keyboardDidHide()

        XCTAssertEqual(presenter.presented.map(\.frame), [CGRect(x: 100, y: 560, width: 200, height: 50)])
        XCTAssertEqual(sut.menuMessageId, message.id)
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
}
