//
//  FeedScrollAnchoringTests.swift
//  ChatikTests
//

import UIKit
import XCTest
@testable import Chatik

@MainActor
final class FeedBottomTrackerTests: XCTestCase {
    private var sut: FeedBottomTracker!

    override func setUp() {
        super.setUp()
        sut = FeedBottomTracker()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// Кейс: якорь низа сообщил кадр раньше, чем лента — свою высоту; затем пришла высота 800, якорь у низа.
    /// Ожидание: до высоты лента считается внизу и кнопки нет; после — внизу, расстояние 0.
    func test_anchorBeforeViewport_staysAtBottom() {
        sut.anchorDidMove(minY: 800)

        XCTAssertTrue(sut.isAtBottom)
        XCTAssertFalse(sut.isBeyondThreshold)
        sut.viewportDidChange(height: 800)
        XCTAssertTrue(sut.isAtBottom)
        XCTAssertEqual(sut.distanceFromBottom, 0)
    }

    /// Кейс: высота ленты 800; якорь низа на разном расстоянии от низа видимой области.
    /// Ожидание: до допуска 24 pt включительно лента внизу, дальше — нет.
    func test_isAtBottom_usesTolerance() {
        let cases: [(distance: CGFloat, isAtBottom: Bool)] = [
            (0, true),
            (24, true),
            (25, false),
            (400, false),
        ]
        sut.viewportDidChange(height: 800)

        for testCase in cases {
            sut.anchorDidMove(minY: 800 + testCase.distance)

            XCTAssertEqual(sut.isAtBottom, testCase.isAtBottom, "\(testCase.distance)")
        }
    }

    /// Кейс: высота ленты 800; лента отлистана на разное расстояние от низа.
    /// Ожидание: кнопка по порогу — дальше 1,5 высоты (1200 pt); переход без анимации — дальше 2,5 высоты (2000 pt).
    func test_thresholds_relativeToViewport() {
        let cases: [(distance: CGFloat, isBeyondThreshold: Bool, shouldJump: Bool)] = [
            (1200, false, false),
            (1201, true, false),
            (2000, true, false),
            (2001, true, true),
        ]
        sut.viewportDidChange(height: 800)

        for testCase in cases {
            sut.anchorDidMove(minY: 800 + testCase.distance)

            XCTAssertEqual(sut.isBeyondThreshold, testCase.isBeyondThreshold, "\(testCase.distance)")
            XCTAssertEqual(sut.shouldJumpToBottom, testCase.shouldJump, "\(testCase.distance)")
        }
    }
}

@MainActor
final class FeedOffsetKeeperTests: XCTestCase {
    private var now = ContinuousClock.now
    private var scrollView: UIScrollView!
    private var compensations = 0
    private var sut: FeedOffsetKeeper!

    private let first = MessageClientKey(senderId: 2, clientId: "client-1")
    private let second = MessageClientKey(senderId: 2, clientId: "client-2")

    override func setUp() {
        super.setUp()
        now = .now
        compensations = 0
        scrollView = UIScrollView()
        sut = FeedOffsetKeeper(now: { [unowned self] in now })
        sut.attach(scrollView)
        sut.viewportDidChange(height: 800)
        sut.onCompensation = { [unowned self] in compensations += 1 }
    }

    override func tearDown() {
        sut = nil
        scrollView = nil
        super.tearDown()
    }

    /// Кейс: лента не внизу; видимая строка стала якорем, затем раскладка сдвинула её в содержимом на 120 pt.
    /// Ожидание: `contentOffset` сдвинут на те же 120 pt, компенсация сообщена один раз.
    func test_holding_compensatesLayoutShift() {
        sut.isHolding = true

        sut.rowDidMove(first, contentMinY: 100, visualMinY: 300)
        sut.rowDidMove(first, contentMinY: 220, visualMinY: 300)

        XCTAssertEqual(scrollView.contentOffset.y, 120)
        XCTAssertEqual(compensations, 1)
    }

    /// Кейс: лента внизу (удержания нет); строка сдвинулась в содержимом.
    /// Ожидание: `contentOffset` не меняется.
    func test_notHolding_doesNotCompensate() {
        sut.rowDidMove(first, contentMinY: 100, visualMinY: 300)
        sut.rowDidMove(first, contentMinY: 220, visualMinY: 300)

        XCTAssertEqual(scrollView.contentOffset.y, 0)
        XCTAssertEqual(compensations, 0)
    }

    /// Кейс: лента возвращается к низу; строки сдвигаются вставкой. Затем срок возврата вышел, а низа лента
    /// не достигла (прокрутку прервал жест), и строка снова сдвинулась.
    /// Ожидание: во время возврата сдвиги не компенсируются; после срока якорь выбирается заново и сдвиг
    /// компенсируется.
    func test_returnToBottom_suspendsCompensationUntilTimeout() {
        sut.isHolding = true
        sut.rowDidMove(first, contentMinY: 100, visualMinY: 300)

        sut.beginReturnToBottom()
        sut.rowDidMove(first, contentMinY: 220, visualMinY: 300)
        XCTAssertEqual(scrollView.contentOffset.y, 0)

        now += FeedOffsetKeeper.returnToBottomTimeout
        sut.rowDidMove(second, contentMinY: 400, visualMinY: 500)
        sut.rowDidMove(second, contentMinY: 450, visualMinY: 500)
        XCTAssertEqual(scrollView.contentOffset.y, 50)
        XCTAssertEqual(compensations, 1)
    }

    /// Кейс: возврат к низу начат, лента дошла до низа (удержание снято), затем снова ушла от низа.
    /// Ожидание: возврат завершён вместе со снятием удержания — сдвиг сразу компенсируется, не дожидаясь срока.
    func test_reachingBottom_endsReturn() {
        sut.isHolding = true
        sut.beginReturnToBottom()

        sut.isHolding = false
        sut.isHolding = true
        sut.rowDidMove(first, contentMinY: 100, visualMinY: 300)
        sut.rowDidMove(first, contentMinY: 130, visualMinY: 300)

        XCTAssertEqual(scrollView.contentOffset.y, 30)
    }
}
