//
//  DeliveryCheckmarksShapeTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class DeliveryCheckmarksShapeTests: XCTestCase {
    /// Кейс: одна галочка (прогресс прочтения 0).
    /// Ожидание: левой галочки нет, у правой короткий штрих полный — от уровня 0,52 высоты.
    func test_delivered_hasOnlyFullSecondCheck() {
        XCTAssertTrue(DeliveryCheckmarksShape.firstCheck(progress: 0).isEmpty)
        let second = DeliveryCheckmarksShape.secondCheck(progress: 0)
        XCTAssertEqual(second.first?.y ?? 0, 0.52, accuracy: 0.0001)
    }

    /// Кейс: две галочки (прогресс прочтения 1).
    /// Ожидание: левая галочка целиком — три точки; короткий штрих правой начинается на длинном штрихе левой.
    func test_read_secondCheckStubTouchesFirstCheck() throws {
        let first = DeliveryCheckmarksShape.firstCheck(progress: 1)
        XCTAssertEqual(first.count, 3)
        let stub = try XCTUnwrap(DeliveryCheckmarksShape.secondCheck(progress: 1).first)
        let b = first[1], c = first[2]
        // Точка на прямой b → c: векторное произведение (c − b) × (stub − b) равно нулю.
        let cross = (c.x - b.x) * (stub.y - b.y) - (c.y - b.y) * (stub.x - b.x)
        XCTAssertEqual(cross, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(stub.y, 0.52)
    }

    /// Кейс: середина анимации прочтения.
    /// Ожидание: левая галочка дорисована частично — короче целой, но не пустая.
    func test_midAnimation_firstCheckIsPartial() {
        let partial = DeliveryCheckmarksShape.firstCheck(progress: 0.5)
        let full = DeliveryCheckmarksShape.firstCheck(progress: 1)

        XCTAssertFalse(partial.isEmpty)
        XCTAssertLessThan(length(partial), length(full))
    }

    /// Кейс: прогресс за пределами 0…1 (перелёт пружинной анимации).
    /// Ожидание: значения ограничиваются — как при 0 и 1.
    func test_progressOutOfRange_isClamped() {
        XCTAssertTrue(DeliveryCheckmarksShape.firstCheck(progress: -0.2).isEmpty)
        XCTAssertEqual(DeliveryCheckmarksShape.firstCheck(progress: 1.3), DeliveryCheckmarksShape.firstCheck(progress: 1))
        XCTAssertEqual(DeliveryCheckmarksShape.secondCheck(progress: 1.3), DeliveryCheckmarksShape.secondCheck(progress: 1))
    }

    /// Длина ломаной.
    /// - Parameter points: точки ломаной.
    private func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
    }
}
