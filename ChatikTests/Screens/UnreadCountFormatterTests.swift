//
//  UnreadCountFormatterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class UnreadCountFormatterTests: XCTestCase {
    /// Кейс: 0, 1, 99, 100 и 1000 непрочитанных.
    /// Ожидание: при 0 счётчика нет; до 99 — точное число; выше — «99+».
    func test_text_formatsCounts() {
        let cases: [(count: Int, text: String?)] = [
            (0, nil),
            (1, "1"),
            (99, "99"),
            (100, "99+"),
            (1000, "99+"),
        ]

        for testCase in cases {
            XCTAssertEqual(UnreadCountFormatter.text(for: testCase.count), testCase.text, "\(testCase.count)")
        }
    }

    /// Кейс: подпись счётчика из `Common.stringsdict` русского языка — 1, 3, 5, 21 и 150 непрочитанных.
    /// Ожидание: точное число, без «99+», в нужной форме множественного числа.
    func test_unreadCountLabel_russianPluralForms() throws {
        let bundle = try localizedBundle(for: .ru)
        let cases: [(count: Int, label: String)] = [
            (1, "1 непрочитанное сообщение"),
            (3, "3 непрочитанных сообщения"),
            (5, "5 непрочитанных сообщений"),
            (21, "21 непрочитанное сообщение"),
            (150, "150 непрочитанных сообщений"),
        ]

        for testCase in cases {
            let label = Localized.plural("common.unread_count", table: "Common", count: testCase.count, bundle: bundle, locale: AppLanguage.ru.locale)
            XCTAssertEqual(label, testCase.label, "\(testCase.count)")
        }
    }

    /// Кейс: подпись счётчика из `Common.stringsdict` английского языка — 1 и 2 непрочитанных.
    /// Ожидание: формы one и other английского языка.
    func test_unreadCountLabel_englishPluralForms() throws {
        let bundle = try localizedBundle(for: .en)
        let label: (Int) -> String = {
            Localized.plural("common.unread_count", table: "Common", count: $0, bundle: bundle, locale: AppLanguage.en.locale)
        }

        XCTAssertEqual(label(1), "1 unread message")
        XCTAssertEqual(label(2), "2 unread messages")
    }

    /// Кейс: подпись VoiceOver при 0 непрочитанных.
    /// Ожидание: подписи нет — счётчик не показывается.
    func test_accessibilityLabel_zero_isNil() {
        XCTAssertNil(UnreadCountFormatter.accessibilityLabel(for: 0))
    }

    /// Бандл строк указанного языка из бандла приложения.
    /// - Parameter language: язык.
    private func localizedBundle(for language: AppLanguage) throws -> Bundle {
        let appBundle = Bundle(for: ChatViewModel.self)
        let path = try XCTUnwrap(appBundle.path(forResource: language.rawValue, ofType: "lproj"), "нет \(language.rawValue).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }
}
