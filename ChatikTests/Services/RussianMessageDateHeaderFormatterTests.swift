//
//  RussianMessageDateHeaderFormatterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class RussianMessageDateHeaderFormatterTests: XCTestCase {
    private let calendar = Calendar.stub()
    private lazy var sut = RussianMessageDateHeaderFormatter(calendar: calendar)

    /// Кейс: текущая дата — четверг, 15 октября 2026; сообщения из таблицы примеров.
    /// Ожидание: заголовки один в один как в таблице.
    func test_string_examplesFromOctober() {
        let now = calendar.date(2026, 10, 15)
        let cases: [(date: Date, expected: String)] = [
            (calendar.date(2026, 10, 15), "Сегодня, 15 октября"),
            (calendar.date(2026, 10, 14), "Вчера, 14 октября"),
            (calendar.date(2026, 10, 13), "Вторник, 13 октября"),
            (calendar.date(2026, 10, 9), "Пятница, 9 октября"),
            (calendar.date(2026, 10, 8), "8 октября"),
            (calendar.date(2025, 12, 30), "30 декабря 2025 г."),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.string(from: testCase.date, now: now), testCase.expected)
        }
    }

    /// Кейс: текущая дата — суббота, 2 января 2027; сообщения конца прошлого года.
    /// Ожидание: заголовки один в один как в таблице перехода через год.
    func test_string_examplesAcrossYear() {
        let now = calendar.date(2027, 1, 2)
        let cases: [(date: Date, expected: String)] = [
            (calendar.date(2027, 1, 2), "Сегодня, 2 января"),
            (calendar.date(2027, 1, 1), "Вчера, 1 января"),
            (calendar.date(2026, 12, 31), "Четверг, 31 декабря 2026 г."),
            (calendar.date(2026, 12, 30), "Среда, 30 декабря 2026 г."),
            (calendar.date(2026, 12, 26), "26 декабря 2026 г."),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.string(from: testCase.date, now: now), testCase.expected)
        }
    }

    /// Кейс: сегодня 1 января 2027, сообщение отправлено 31 декабря.
    /// Ожидание: «Вчера, 31 декабря 2026 г.».
    func test_string_yesterdayOnFirstOfJanuary_includesYear() {
        let title = sut.string(from: calendar.date(2026, 12, 31), now: calendar.date(2027, 1, 1))

        XCTAssertEqual(title, "Вчера, 31 декабря 2026 г.")
    }

    /// Кейс: календарь устройства не григорианский (еврейский — 13 месяцев, буддийский, японский) с тем же
    /// часовым поясом; сегодня 15 октября 2026.
    /// Ожидание: заголовки как при григорианском календаре — без падения и с григорианским годом.
    func test_string_nonGregorianDeviceCalendar_usesGregorian() {
        let identifiers: [Calendar.Identifier] = [
            .hebrew,
            .buddhist,
            .japanese,
        ]
        let now = calendar.date(2026, 10, 15)

        for identifier in identifiers {
            var deviceCalendar = Calendar(identifier: identifier)
            deviceCalendar.timeZone = calendar.timeZone
            let sut = RussianMessageDateHeaderFormatter(calendar: deviceCalendar)

            XCTAssertEqual(sut.string(from: calendar.date(2026, 10, 14), now: now), "Вчера, 14 октября", "\(identifier)")
            XCTAssertEqual(sut.string(from: calendar.date(2025, 12, 30), now: now), "30 декабря 2025 г.", "\(identifier)")
        }
    }
}
