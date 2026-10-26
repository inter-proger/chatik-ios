//
//  GroupValidatorTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class GroupValidatorTests: XCTestCase {
    /// Кейс: название из пробелов, NBSP, zero-width и BOM; название ровно 128 кодовых точек; 129.
    /// Ожидание: первое пустое, второе подходит, третье длиннее лимита.
    func test_validateName_trimsLikeServerAndCountsScalars() {
        let cases: [(name: String, expected: GroupFieldError?)] = [
            (" \u{00A0}\u{200B}\u{FEFF}\n", .empty),
            (String(repeating: "а", count: 128), nil),
            (String(repeating: "а", count: 129), .tooLong(maxLength: 128)),
            ("  Команда  ", nil),
        ]

        for (name, expected) in cases {
            XCTAssertEqual(GroupValidator.validateName(name), expected, name)
        }
    }

    /// Кейс: название из 43 флагов (по 2 кодовые точки) — 43 графемы, 86 кодовых точек; из 65 флагов — 130.
    /// Ожидание: длина считается по кодовым точкам, как на сервере: 43 флага подходят, 65 — нет.
    func test_validateName_emojiCountedAsCodePoints() {
        let flag = "🇷🇺"

        XCTAssertNil(GroupValidator.validateName(String(repeating: flag, count: 43)))
        XCTAssertEqual(GroupValidator.validateName(String(repeating: flag, count: 65)), .tooLong(maxLength: 128))
    }

    /// Кейс: пустое описание, описание ровно 1024 и 1025 кодовых точек.
    /// Ожидание: пустое и 1024 подходят, 1025 — длиннее лимита.
    func test_validateDescription_limit() {
        XCTAssertNil(GroupValidator.validateDescription("   "))
        XCTAssertNil(GroupValidator.validateDescription(String(repeating: "a", count: 1024)))
        XCTAssertEqual(GroupValidator.validateDescription(String(repeating: "a", count: 1025)), .tooLong(maxLength: 1024))
    }

    /// Кейс: обрезка текста для отправки.
    /// Ожидание: обрезаются пробелы, переводы строк и невидимые символы по краям; внутри текст не меняется.
    func test_normalized_trimsEdgesOnly() {
        XCTAssertEqual(GroupValidator.normalized("\u{200B} Рабочие  вопросы \n\u{FEFF}"), "Рабочие  вопросы")
    }
}
