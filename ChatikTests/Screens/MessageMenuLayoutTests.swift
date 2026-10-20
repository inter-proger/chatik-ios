//
//  MessageMenuLayoutTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageMenuLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 8, y: 60, width: 386, height: 760)
    private let menuSize = CGSize(width: 250, height: 44)

    /// Кейс: под пузырём хватает места для списка.
    /// Ожидание: пузырь на месте, список под ним через промежуток.
    func test_roomBelow_menuBelowBubble() {
        let bubble = CGRect(x: 150, y: 300, width: 220, height: 60)

        let sut = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)

        XCTAssertEqual(sut.bubbleFrame, bubble)
        XCTAssertEqual(sut.menuFrame.minY, bubble.maxY + MessageMenuLayout.spacing)
    }

    /// Кейс: пузырь у нижней границы, сверху места достаточно.
    /// Ожидание: пузырь на месте, список над ним через промежуток.
    func test_noRoomBelow_menuAboveBubble() {
        let bubble = CGRect(x: 150, y: 740, width: 220, height: 60)

        let sut = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)

        XCTAssertEqual(sut.bubbleFrame, bubble)
        XCTAssertEqual(sut.menuFrame.maxY, bubble.minY - MessageMenuLayout.spacing)
    }

    /// Кейс: пузырь почти во всю высоту — места нет ни снизу, ни сверху.
    /// Ожидание: пузырь поднят так, что список встаёт под ним вплотную к нижней границе; пузырь не выше верхней.
    func test_noRoomAnywhere_bubbleShiftedUp() {
        let bubble = CGRect(x: 150, y: 90, width: 220, height: 700)

        let sut = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)

        XCTAssertEqual(sut.bubbleFrame.minY, bounds.maxY - menuSize.height - MessageMenuLayout.spacing - bubble.height)
        XCTAssertGreaterThanOrEqual(sut.bubbleFrame.minY, bounds.minY)
        XCTAssertEqual(sut.menuFrame.maxY, bounds.maxY)
    }

    /// Кейс: пузырь выше всей области.
    /// Ожидание: пузырь у верхней границы, список не выходит за нижнюю.
    func test_bubbleTallerThanBounds_menuStaysInside() {
        let bubble = CGRect(x: 150, y: 20, width: 220, height: 900)

        let sut = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)

        XCTAssertEqual(sut.bubbleFrame.minY, bounds.minY)
        XCTAssertEqual(sut.menuFrame.maxY, bounds.maxY)
    }

    /// Кейс: своё и входящее сообщение.
    /// Ожидание: у своего список по правому краю пузыря, у входящего — по левому.
    func test_horizontalAlignment_followsMessageSide() {
        let bubble = CGRect(x: 120, y: 300, width: 200, height: 60)

        let outgoing = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)
        let incoming = MessageMenuLayout(bubbleFrame: bubble, menuSize: menuSize, bounds: bounds, isOutgoing: false)

        XCTAssertEqual(outgoing.menuFrame.maxX, bubble.maxX)
        XCTAssertEqual(incoming.menuFrame.minX, bubble.minX)
    }

    /// Кейс: узкий пузырь у края — список по его краю вышел бы за границу.
    /// Ожидание: список прижат к границе.
    func test_menuClampedToBounds() {
        let leftBubble = CGRect(x: 10, y: 300, width: 60, height: 40)
        let rightBubble = CGRect(x: 330, y: 300, width: 60, height: 40)

        let outgoing = MessageMenuLayout(bubbleFrame: leftBubble, menuSize: menuSize, bounds: bounds, isOutgoing: true)
        let incoming = MessageMenuLayout(bubbleFrame: rightBubble, menuSize: menuSize, bounds: bounds, isOutgoing: false)

        XCTAssertEqual(outgoing.menuFrame.minX, bounds.minX)
        XCTAssertEqual(incoming.menuFrame.maxX, bounds.maxX)
    }
}
