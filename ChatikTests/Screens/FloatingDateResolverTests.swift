//
//  FloatingDateResolverTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class FloatingDateResolverTests: XCTestCase {
    /// Строка ленты и её визуальный кадр.
    private typealias RowFrame = (row: FloatingDateRow, frame: CGRect)

    private let line: CGFloat = 8
    private let today = MessageDaySectionID(day: Date(timeIntervalSince1970: 1_000_000), occurrence: 0)
    private let yesterday = MessageDaySectionID(day: Date(timeIntervalSince1970: 900_000), occurrence: 0)
    private lazy var titles = [today: "Сегодня, 15 октября", yesterday: "Вчера, 14 октября"]

    /// Кейс: у линии плашки сообщения сегодняшнего дня, их заголовок ниже линии.
    /// Ожидание: заголовок на месте — плашка не нужна.
    func test_resolve_headerBelowLine_isNil() {
        let rows = [
            header(today, minY: 40),
            message("1", today, minY: 70),
        ]

        XCTAssertNil(resolve(rows))
    }

    /// Кейс: верх заголовка ровно на линии плашки (и в пределах допуска выше неё).
    /// Ожидание: заголовок стоит на месте плашки — плашка не нужна.
    func test_resolve_headerExactlyOnLine_isNil() {
        let minYs: [CGFloat] = [
            8,
            7.8,
        ]

        for minY in minYs {
            XCTAssertNil(resolve([header(today, minY: minY), message("1", today, minY: minY + 30)]), "\(minY)")
        }
    }

    /// Кейс: заголовок сегодняшнего дня выше линии — частично или целиком; у линии его сообщения.
    /// Ожидание: плашка с датой сегодняшнего дня.
    func test_resolve_headerAboveLine_isTopSection() {
        let headerMinYs: [CGFloat] = [
            0,
            -40,
        ]

        for minY in headerMinYs {
            let rows = [header(today, minY: minY), message("1", today, minY: minY + 30)]
            XCTAssertEqual(resolve(rows), FloatingDate(section: today, title: "Сегодня, 15 октября"), "\(minY)")
        }
    }

    /// Кейс: заголовок верхней секции не выложен — ушёл далеко за верхний край.
    /// Ожидание: плашка с датой этой секции.
    func test_resolve_headerNotLaidOut_isTopSection() {
        let rows = [
            message("2", today, minY: -10),
            message("1", today, minY: 30),
        ]

        XCTAssertEqual(resolve(rows), FloatingDate(section: today, title: "Сегодня, 15 октября"))
    }

    /// Кейс: линию пересекают сообщения вчерашнего дня, его заголовок выше; заголовок сегодняшнего — ниже линии.
    /// Ожидание: плашка со вчерашней датой — верхняя секция та, чья строка у линии.
    func test_resolve_lineBetweenSections_isSectionAtLine() {
        let rows = [
            message("1", yesterday, minY: -10),
            header(today, minY: 40),
            message("2", today, minY: 70),
        ]

        XCTAssertEqual(resolve(rows), FloatingDate(section: yesterday, title: "Вчера, 14 октября"))
    }

    /// Кейс: строки целиком выше линии не учитываются; строк нет вообще.
    /// Ожидание: без строк у линии и ниже плашка не нужна.
    func test_resolve_noRows_isNil() {
        XCTAssertNil(resolve([]))
        XCTAssertNil(resolve([message("1", today, minY: -60)]))
    }

    // MARK: - Helpers

    /// Дата для плашки по строкам ленты.
    /// - Parameter rows: строки с кадрами.
    private func resolve(_ rows: [RowFrame]) -> FloatingDate? {
        FloatingDateResolver.resolve(rows: Dictionary(uniqueKeysWithValues: rows), titles: titles, line: line)
    }

    /// Заголовок секции высотой 20.
    /// - Parameters:
    ///   - section: секция.
    ///   - minY: верх заголовка.
    private func header(_ section: MessageDaySectionID, minY: CGFloat) -> RowFrame {
        (FloatingDateRow(kind: .header, section: section), CGRect(x: 100, y: minY, width: 120, height: 20))
    }

    /// Сообщение высотой 28.
    /// - Parameters:
    ///   - clientId: `clientId` сообщения.
    ///   - section: секция.
    ///   - minY: верх строки.
    private func message(_ clientId: String, _ section: MessageDaySectionID, minY: CGFloat) -> RowFrame {
        let row = FloatingDateRow(kind: .message(MessageClientKey(senderId: 1, clientId: clientId)), section: section)
        return (row, CGRect(x: 0, y: minY, width: 300, height: 28))
    }
}
