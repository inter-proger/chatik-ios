//
//  SingleLineTextTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class SingleLineTextTests: XCTestCase {
    /// Кейс: тексты с переводами строк, повторяющимися пробелами и пробелами по краям.
    /// Ожидание: одна строка, пробельные символы сведены к одному пробелу, края обрезаны.
    func test_make_collapsesWhitespace() {
        let cases: [(input: String, expected: String)] = [
            ("Привет", "Привет"),
            ("  Привет  ", "Привет"),
            ("Первая\nвторая\n\nтретья", "Первая вторая третья"),
            ("a \t  b", "a b"),
            (" \n ", ""),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(SingleLineText.make(input, maxLength: 200), expected, input)
        }
    }

    /// Кейс: текст длиннее `maxLength`, перед ним пробелы.
    /// Ожидание: берутся первые `maxLength` символов после пробелов в начале.
    func test_make_limitsLengthAfterLeadingWhitespace() {
        let text = "   " + String(repeating: "а", count: 10)

        XCTAssertEqual(SingleLineText.make(text, maxLength: 4), "аааа")
    }
}
