//
//  FloatingDateTrackerTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

/// Подавление плашки на iOS 17: прокрутка определяется по кадрам строк, а сдвиги раскладки без жеста ею не считаются.
@MainActor
final class FloatingDateTrackerTests: XCTestCase {
    private var now = ContinuousClock.now
    private var sut: FloatingDateTracker!

    private let today = MessageDaySectionID(day: Date(timeIntervalSince1970: 1_000_000), occurrence: 0)
    private lazy var row = FloatingDateRow(kind: .message(MessageClientKey(senderId: 2, clientId: "client-1")), section: today)

    override func setUp() {
        super.setUp()
        now = .now
        sut = FloatingDateTracker(layoutAnimationDuration: .milliseconds(300), usesScrollPhase: false, now: { [unowned self] in now })
        sut.setTitles([today: "Сегодня, 15 октября"])
        now += FloatingDateTracker.layoutChangeSuppression
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// Кейс: секции известны, окна подавления нет; строка под линией плашки сдвинулась.
    /// Ожидание: это прокрутка — плашка видна.
    func test_rowMoved_withoutSuppression_showsDate() {
        sut.update(row, frame: CGRect(x: 0, y: 0, width: 100, height: 40))

        XCTAssertTrue(sut.isVisible)
    }

    /// Кейс: первый кадр строки пришёл уже с новым номером анимированной раскладки (анимация 0,3 с) — раньше любого
    /// `onChange`; строка сдвигается в той же раскладке через 0,5 с (ещё в окне: 0,3 с анимации + 0,3 с раскладки),
    /// затем через 0,6 с — уже после окна.
    /// Ожидание: во время анимации плашки нет, в том числе на первом кадре; сдвиг после окна — снова прокрутка.
    func test_layoutAnimationFromFrame_suppressesForAnimationAndLayout() {
        sut.update(row, frame: CGRect(x: 0, y: 20, width: 100, height: 40), layoutAnimation: 1)
        XCTAssertFalse(sut.isVisible)

        now += .milliseconds(500)
        sut.update(row, frame: CGRect(x: 0, y: 0, width: 100, height: 40), layoutAnimation: 1)
        XCTAssertFalse(sut.isVisible)

        now += .milliseconds(100)
        sut.update(row, frame: CGRect(x: 0, y: -10, width: 100, height: 40), layoutAnimation: 1)
        XCTAssertTrue(sut.isVisible)
    }

    /// Кейс: идёт окно анимации на 1 с; следом — смена раскладки без анимации (окно 0,3 с); строка сдвинулась
    /// через 0,5 с.
    /// Ожидание: короткое окно не укоротило длинное — плашки нет.
    func test_layoutChange_doesNotShortenAnimationWindow() {
        sut.layoutDidChange(animationDuration: .seconds(1))
        sut.layoutDidChange()

        now += .milliseconds(500)
        sut.update(row, frame: CGRect(x: 0, y: 0, width: 100, height: 40))

        XCTAssertFalse(sut.isVisible)
    }
}
