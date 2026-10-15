//
//  MessageDateHeaderFormatterProviderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageDateHeaderFormatterProviderTests: XCTestCase {
    private let sut = MessageDateHeaderFormatterProvider.default

    /// Кейс: русский язык — без региона и с регионом.
    /// Ожидание: реализация для русского.
    func test_formatter_russian_isRussianImplementation() {
        let locales = [
            "ru",
            "ru_RU",
        ]

        for locale in locales {
            XCTAssertTrue(sut.formatter(locale: Locale(identifier: locale), calendar: .stub()) is RussianMessageDateHeaderFormatter, locale)
        }
    }

    /// Кейс: английский и язык, для которого нет отдельной реализации.
    /// Ожидание: общая реализация на ICU с переданной локалью.
    func test_formatter_otherLanguages_isLocaleImplementation() {
        let locales = [
            "en",
            "de_DE",
        ]

        for locale in locales {
            let formatter = sut.formatter(locale: Locale(identifier: locale), calendar: .stub())
            XCTAssertEqual((formatter as? LocaleMessageDateHeaderFormatter)?.locale, Locale(identifier: locale), locale)
        }
    }
}
