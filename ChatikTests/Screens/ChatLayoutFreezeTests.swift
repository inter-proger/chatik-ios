//
//  ChatLayoutFreezeTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ChatLayoutFreezeTests: XCTestCase {
    /// Высота над открытой клавиатурой.
    private let keyboardShown: CGFloat = 400
    /// Высота без клавиатуры.
    private let keyboardHidden: CGFloat = 700

    /// Кейс: меню нет, клавиатура появляется и прячется.
    /// Ожидание: высота не фиксируется — экран следует за клавиатурой.
    func test_withoutMenu_followsKeyboard() {
        var sut = ChatLayoutFreeze()
        let heights = [
            keyboardHidden,
            keyboardShown,
            keyboardHidden,
        ]

        for height in heights {
            sut.setAvailableHeight(height)
            XCTAssertNil(sut.frozenHeight, "\(height)")
        }
    }

    /// Кейс: клавиатура открыта; пузырь нажат и меню открылось, клавиатура спряталась.
    /// Ожидание: высота зафиксирована на высоте над клавиатурой и не меняется, когда клавиатура прячется.
    func test_menuOpened_keepsHeightWhenKeyboardHides() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)

        sut.setMenuPhase(.pressed)
        sut.setMenuPhase(.open)
        sut.setAvailableHeight(keyboardHidden)

        XCTAssertEqual(sut.frozenHeight, keyboardShown)
    }

    /// Кейс: меню открыто с зафиксированной высотой над клавиатурой; меню закрывается, клавиатура начинает
    /// подниматься (высота над ней уже конечная), затем поднимается до конца.
    /// Ожидание: пока клавиатура поднимается, высота держится; когда поднялась — отпускается.
    func test_menuClosing_releasesWhenKeyboardDidShow() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)
        sut.setMenuPhase(.open)
        sut.setAvailableHeight(keyboardHidden)

        sut.setMenuPhase(.closing)
        sut.setAvailableHeight(keyboardShown)
        XCTAssertEqual(sut.frozenHeight, keyboardShown)
        sut.keyboardDidShow()

        XCTAssertNil(sut.frozenHeight)
    }

    /// Кейс: меню нет или оно открыто без спрятанной клавиатуры; приходит `keyboardDidShow`.
    /// Ожидание: событие ничего не меняет — фиксации нет или она держится до закрытия меню.
    func test_keyboardDidShow_notAwaiting_changesNothing() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)

        sut.keyboardDidShow()
        XCTAssertNil(sut.frozenHeight)
        sut.setMenuPhase(.open)
        sut.keyboardDidShow()

        XCTAssertEqual(sut.frozenHeight, keyboardShown)
    }

    /// Кейс: клавиатуры нет; меню открыто и закрывается выбором «Редактировать», который поднимает клавиатуру.
    /// Ожидание: высота отпускается в начале закрытия — экран сразу следует за поднимающейся клавиатурой.
    func test_menuClosing_withoutKeyboard_releasesImmediately() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardHidden)
        sut.setMenuPhase(.open)

        sut.setMenuPhase(.closing)

        XCTAssertNil(sut.frozenHeight)
        sut.setAvailableHeight(keyboardShown)
        XCTAssertNil(sut.frozenHeight)
    }

    /// Кейс: меню открыто с клавиатурой, закрылось, а клавиатура не вернулась.
    /// Ожидание: по окончании закрытия высота отпускается.
    func test_menuClosed_keyboardNotReturned_releases() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)
        sut.setMenuPhase(.open)
        sut.setAvailableHeight(keyboardHidden)
        sut.setMenuPhase(.closing)

        sut.setMenuPhase(.closed)

        XCTAssertNil(sut.frozenHeight)
    }

    /// Кейс: клавиатура открыта; пузырь нажат, но палец отпущен раньше, чем открылось меню.
    /// Ожидание: на время нажатия высота зафиксирована, при отмене — сразу отпускается.
    func test_pressCancelled_releasesImmediately() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)

        sut.setMenuPhase(.pressed)
        XCTAssertEqual(sut.frozenHeight, keyboardShown)
        sut.setMenuPhase(.closing)

        XCTAssertNil(sut.frozenHeight)
    }

    /// Кейс: на момент закрытия меню высота над клавиатурой отличается от зафиксированной на доли точки.
    /// Ожидание: высота отпускается сразу — расхождение раскладки не считается спрятанной клавиатурой.
    func test_menuClosing_subpointDifference_releases() {
        var sut = ChatLayoutFreeze()
        sut.setAvailableHeight(keyboardShown)
        sut.setMenuPhase(.open)
        sut.setAvailableHeight(keyboardShown + 0.33)

        sut.setMenuPhase(.closing)

        XCTAssertNil(sut.frozenHeight)
    }
}
