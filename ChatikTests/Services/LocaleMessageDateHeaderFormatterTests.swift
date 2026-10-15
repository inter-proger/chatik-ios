//
//  LocaleMessageDateHeaderFormatterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class LocaleMessageDateHeaderFormatterTests: XCTestCase {
    private let calendar = Calendar.stub()

    /// Кейс: локаль `en`, текущая дата — 15 октября 2026; сообщения из таблицы примеров.
    /// Ожидание: заголовки один в один как в колонке English.
    func test_string_english_examplesFromOctober() {
        let sut = LocaleMessageDateHeaderFormatter(locale: Locale(identifier: "en"), calendar: calendar)
        let now = calendar.date(2026, 10, 15)
        let cases: [(date: Date, expected: String)] = [
            (calendar.date(2026, 10, 15), "Today, October 15"),
            (calendar.date(2026, 10, 14), "Yesterday, October 14"),
            (calendar.date(2026, 10, 13), "Tuesday, October 13"),
            (calendar.date(2026, 10, 9), "Friday, October 9"),
            (calendar.date(2026, 10, 8), "October 8"),
            (calendar.date(2025, 12, 30), "December 30, 2025"),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.string(from: testCase.date, now: now), testCase.expected)
        }
    }

    /// Кейс: локаль `en`, текущая дата — 2 января 2027; сообщения конца прошлого года.
    /// Ожидание: заголовки один в один как в колонке English таблицы перехода через год.
    func test_string_english_examplesAcrossYear() {
        let sut = LocaleMessageDateHeaderFormatter(locale: Locale(identifier: "en"), calendar: calendar)
        let now = calendar.date(2027, 1, 2)
        let cases: [(date: Date, expected: String)] = [
            (calendar.date(2027, 1, 2), "Today, January 2"),
            (calendar.date(2027, 1, 1), "Yesterday, January 1"),
            (calendar.date(2026, 12, 31), "Thursday, December 31, 2026"),
            (calendar.date(2026, 12, 30), "Wednesday, December 30, 2026"),
            (calendar.date(2026, 12, 26), "December 26, 2026"),
        ]

        for testCase in cases {
            XCTAssertEqual(sut.string(from: testCase.date, now: now), testCase.expected)
        }
    }

    /// Кейс: локаль `ru` на ICU, текущая дата — 2 января 2027. Вывод ICU может меняться между версиями iOS,
    /// поэтому строки не сравниваются точно.
    /// Ожидание: заголовок с заглавной буквы; «Сегодня»/«Вчера» и день недели — перед числом; год — только там,
    /// где его требуют правила.
    func test_string_russianICU_structure() {
        let sut = LocaleMessageDateHeaderFormatter(locale: Locale(identifier: "ru"), calendar: calendar)
        let now = calendar.date(2027, 1, 2)
        let cases: [(date: Date, prefix: String, day: String, hasYear: Bool)] = [
            (calendar.date(2027, 1, 2), "Сегодня, ", "2", false),
            (calendar.date(2027, 1, 1), "Вчера, ", "1", false),
            (calendar.date(2026, 12, 30), "Среда, ", "30", true),
            (calendar.date(2026, 12, 26), "26", "26", true),
        ]

        for testCase in cases {
            let title = sut.string(from: testCase.date, now: now)
            XCTAssertTrue(title.hasPrefix(testCase.prefix), title)
            XCTAssertTrue(title.contains(testCase.day), title)
            XCTAssertEqual(title.contains("2026"), testCase.hasYear, title)
            XCTAssertEqual(title.first.map { String($0) == String($0).uppercased() }, true, title)
        }
    }
}
