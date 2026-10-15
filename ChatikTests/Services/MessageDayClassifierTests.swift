//
//  MessageDayClassifierTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageDayClassifierTests: XCTestCase {
    private let calendar = Calendar.stub()
    private lazy var sut = MessageDayClassifier(calendar: calendar)

    /// Кейс: текущая дата — четверг, 15 октября 2026, 12:00; сообщения из таблицы примеров.
    /// Ожидание: сегодня, вчера, 2–6 дней назад — неделя, 7 и больше — раньше; год только у прошлого года.
    func test_day_examplesFromOctober() {
        let now = calendar.date(2026, 10, 15)
        let cases: [(date: Date, expected: MessageDay)] = [
            (calendar.date(2026, 10, 15, 9), MessageDay(relation: .today, includesYear: false)),
            (calendar.date(2026, 10, 14), MessageDay(relation: .yesterday, includesYear: false)),
            (calendar.date(2026, 10, 13), MessageDay(relation: .lastWeek, includesYear: false)),
            (calendar.date(2026, 10, 9), MessageDay(relation: .lastWeek, includesYear: false)),
            (calendar.date(2026, 10, 8), MessageDay(relation: .earlier, includesYear: false)),
            (calendar.date(2025, 12, 30), MessageDay(relation: .earlier, includesYear: true)),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.day(of: testCase.date, now: now), testCase.expected, "\(testCase.date)")
        }
    }

    /// Кейс: текущая дата — суббота, 2 января 2027; сообщения конца прошлого года.
    /// Ожидание: дни недели и «раньше» прошлого года — с годом, вчера и сегодня — без.
    func test_day_examplesAcrossYear() {
        let now = calendar.date(2027, 1, 2)
        let cases: [(date: Date, expected: MessageDay)] = [
            (calendar.date(2027, 1, 2), MessageDay(relation: .today, includesYear: false)),
            (calendar.date(2027, 1, 1), MessageDay(relation: .yesterday, includesYear: false)),
            (calendar.date(2026, 12, 31), MessageDay(relation: .lastWeek, includesYear: true)),
            (calendar.date(2026, 12, 30), MessageDay(relation: .lastWeek, includesYear: true)),
            (calendar.date(2026, 12, 26), MessageDay(relation: .earlier, includesYear: true)),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.day(of: testCase.date, now: now), testCase.expected, "\(testCase.date)")
        }
    }

    /// Кейс: сегодня 1 января 2027, сообщение отправлено 31 декабря.
    /// Ожидание: вчера, с годом — вчерашний день в прошлом году.
    func test_day_yesterdayOnFirstOfJanuary_includesYear() {
        let day = sut.day(of: calendar.date(2026, 12, 31, 23, 50), now: calendar.date(2027, 1, 1, 0, 10))

        XCTAssertEqual(day, MessageDay(relation: .yesterday, includesYear: true))
    }

    /// Кейс: границы суток — вчера в 23:59 и сегодня в 00:00, текущее время 00:01.
    /// Ожидание: дни считаются по календарю, а не по 24 часам: 23:59 — вчера, 00:00 — сегодня.
    func test_day_midnightBoundaries() {
        let now = calendar.date(2026, 10, 15, 0, 1)

        XCTAssertEqual(sut.day(of: calendar.date(2026, 10, 14, 23, 59), now: now).relation, .yesterday)
        XCTAssertEqual(sut.day(of: calendar.date(2026, 10, 15, 0, 0), now: now).relation, .today)
    }

    /// Кейс: сообщение на минуту позже текущего времени (часы устройства отстают) и на следующий день.
    /// Ожидание: та же минута позже — сегодня; следующий день — раньше, как обычная дата.
    func test_day_futureDate() {
        let now = calendar.date(2026, 10, 15)

        XCTAssertEqual(sut.day(of: now.addingTimeInterval(60), now: now).relation, .today)
        XCTAssertEqual(sut.day(of: calendar.date(2026, 10, 16), now: now), MessageDay(relation: .earlier, includesYear: false))
    }

    /// Кейс: Берлин, 29 марта 2026 переход на летнее время — в сутках 23 часа; сейчас 30 марта, 00:30.
    /// Ожидание: 29 марта, 00:30 — вчера, хотя прошло меньше 24 часов; 28 марта, 23:30 — 2 дня назад.
    func test_day_daylightSavingTransition() {
        let berlin = Calendar.stub(timeZone: "Europe/Berlin")
        let sut = MessageDayClassifier(calendar: berlin)
        let now = berlin.date(2026, 3, 30, 0, 30)

        XCTAssertEqual(sut.day(of: berlin.date(2026, 3, 29, 0, 30), now: now).relation, .yesterday)
        XCTAssertEqual(sut.day(of: berlin.date(2026, 3, 28, 23, 30), now: now).relation, .lastWeek)
    }
}
