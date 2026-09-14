//
//  AppLanguageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class AppLanguageTests: XCTestCase {
    /// Кейс: первый предпочитаемый язык системы — русский или английский (с регионом и без).
    /// Ожидание: выбирается соответствующий язык приложения.
    func test_systemDefault_supportedLanguage_isPicked() {
        let cases: [(preferred: [String], expected: AppLanguage)] = [
            (["ru"], .ru),
            (["ru-RU", "en-US"], .ru),
            (["en"], .en),
            (["en-GB", "ru-RU"], .en),
        ]

        for testCase in cases {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: testCase.preferred), testCase.expected, "\(testCase.preferred)")
        }
    }

    /// Кейс: первый предпочитаемый язык не поддерживается (даже если дальше в списке есть русский) или список пуст.
    /// Ожидание: английский как язык по умолчанию.
    func test_systemDefault_unsupportedOrEmpty_fallsBackToEnglish() {
        let cases: [[String]] = [
            ["de-DE"],
            ["fr-FR", "ru-RU"],
            ["zh-Hans-CN"],
            [],
        ]

        for preferred in cases {
            XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: preferred), .en, "\(preferred)")
        }
    }
}
