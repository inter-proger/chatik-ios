//
//  MessageTimeFormatterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageTimeFormatterTests: XCTestCase {
    private let calendar = Calendar.stub()
    private lazy var now = calendar.date(2026, 10, 15)

    /// Кейс: сообщения сегодняшнего, вчерашнего и прошлогоднего дня, отправленные в 18:40; язык `ru`.
    /// Ожидание: `timeString(from:locale:calendar:)` — только время в 24-часовом формате, без даты.
    func test_timeString_russian_isTimeOnly() {
        let locale = Locale(identifier: "ru")
        let dates = [
            calendar.date(2026, 10, 15, 18, 40),
            calendar.date(2026, 10, 14, 18, 40),
            calendar.date(2025, 12, 30, 18, 40),
        ]

        for date in dates {
            XCTAssertEqual(MessageTimeFormatter.timeString(from: date, locale: locale, calendar: calendar), "18:40", "\(date)")
        }
    }

    /// Кейс: вчерашнее сообщение в 18:40; язык `en`.
    /// Ожидание: только время в 12-часовом формате.
    func test_timeString_english_is12Hour() {
        let date = calendar.date(2026, 10, 14, 18, 40)

        let time = MessageTimeFormatter.timeString(from: date, locale: Locale(identifier: "en"), calendar: calendar)

        XCTAssertTrue(time.hasPrefix("6:40"), time)
        XCTAssertTrue(time.hasSuffix("PM"), time)
    }

    /// Кейс: сообщения сегодняшнего, прошлого в этом году и прошлогоднего дня; язык `ru`.
    /// Ожидание: `string(from:)` — прежний формат списка чатов: сегодня только время, в этом году день, месяц
    /// и время, раньше ещё и год.
    func test_string_keepsChatListFormat() {
        let sut = MessageTimeFormatter(locale: Locale(identifier: "ru"), calendar: calendar, now: now)

        XCTAssertEqual(sut.string(from: calendar.date(2026, 10, 15, 18, 40)), "18:40")
        let thisYear = sut.string(from: calendar.date(2026, 10, 13, 18, 40))
        XCTAssertTrue(thisYear.contains("13") && thisYear.contains("18:40") && !thisYear.contains("2026"), thisYear)
        let lastYear = sut.string(from: calendar.date(2025, 12, 30, 18, 40))
        XCTAssertTrue(lastYear.contains("2025") && lastYear.contains("18:40"), lastYear)
    }
}
