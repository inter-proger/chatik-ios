//
//  MessageTextValidatorTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageTextValidatorTests: XCTestCase {
    private let sut = MessageTextValidator()

    /// Кейс: обычные тексты — одно слово, многострочный, с эмодзи, ровно на лимите.
    /// Ожидание: все валидны.
    func test_validate_acceptsTextWithinLimit() {
        let texts = [
            "Привет!",
            "Строка 1\nСтрока 2",
            "Ок 👍",
            String(repeating: "a", count: MessageTextValidator.maxLength),
        ]

        for text in texts {
            XCTAssertNil(sut.validate(text), text)
        }
    }

    /// Кейс: пустая строка и строки из одних пробелов, табуляций и переводов строк.
    /// Ожидание: ошибка `.empty` — сервер обрезает их до пустой строки.
    func test_validate_blank_returnsEmpty() {
        let texts = [
            "",
            "   ",
            "\n\n",
            " \t\n ",
        ]

        for text in texts {
            XCTAssertEqual(sut.validate(text), .empty, text.debugDescription)
        }
    }

    /// Кейс: текст на один символ длиннее лимита.
    /// Ожидание: ошибка `.tooLong` с лимитом сервера.
    func test_validate_overLimit_returnsTooLong() {
        let text = String(repeating: "a", count: MessageTextValidator.maxLength + 1)

        XCTAssertEqual(sut.validate(text), .tooLong(maxLength: MessageTextValidator.maxLength))
    }

    /// Кейс: текст на лимите, окружённый пробелами и переводами строк.
    /// Ожидание: валиден — краевые пробелы отсекаются до подсчёта длины, как на сервере.
    func test_validate_surroundingWhitespace_notCounted() {
        let text = "  \n" + String(repeating: "a", count: MessageTextValidator.maxLength) + "\n  "

        XCTAssertNil(sut.validate(text))
    }

    /// Кейс: 600 эмодзи «семья» — 600 графем, но каждая из 7 code points (всего 4200).
    /// Ожидание: ошибка `.tooLong` — длина считается в code points, как на сервере, а не в графемах.
    func test_validate_multiScalarGraphemes_countedByCodePoints() {
        let family = "👨‍👩‍👧‍👦"
        let text = String(repeating: family, count: 600)

        XCTAssertEqual(text.count, 600)
        XCTAssertEqual(sut.validate(text), .tooLong(maxLength: MessageTextValidator.maxLength))
    }
}
