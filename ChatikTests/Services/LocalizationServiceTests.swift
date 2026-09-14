//
//  LocalizationServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class LocalizationServiceTests: XCTestCase {
    /// Кейс: язык ещё не выбирался, системный — русский / английский.
    /// Ожидание: до и после `restore()` используется системный язык.
    func test_init_withoutSavedLanguage_usesSystemLanguage() async {
        let sut = LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru)
        XCTAssertEqual(sut.language, .ru)

        await sut.restore()

        XCTAssertEqual(sut.language, .ru)
    }

    /// Кейс: в `UserDefaults` сохранён английский, системный — русский.
    /// Ожидание: до `restore()` — системный, после — сохранённый.
    func test_restore_appliesSavedLanguage() async {
        let sut = LocalizationService(userDefaultsService: UserDefaultsServiceMock(language: .en), systemLanguage: .ru)
        XCTAssertEqual(sut.language, .ru)

        await sut.restore()

        XCTAssertEqual(sut.language, .en)
    }

    /// Кейс: пользователь выбрал язык.
    /// Ожидание: язык применён сразу и сохранён в `UserDefaults`.
    func test_setLanguage_appliesAndPersists() async {
        let defaults = UserDefaultsServiceMock()
        let sut = LocalizationService(userDefaultsService: defaults, systemLanguage: .ru)

        await sut.setLanguage(.en)

        let stored = await defaults.language()
        XCTAssertEqual(sut.language, .en)
        XCTAssertEqual(stored, .en)
    }

    /// Кейс: язык переключён с русского на английский.
    /// Ожидание: `bundle` указывает на `en.lproj`, и одна и та же строка читается на разных языках.
    func test_bundle_followsLanguage() async {
        let sut = LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru)
        let russian = sut.bundle.localizedString(forKey: "auth.title.login", value: nil, table: "Auth")

        await sut.setLanguage(.en)
        let english = sut.bundle.localizedString(forKey: "auth.title.login", value: nil, table: "Auth")

        XCTAssertTrue(sut.bundle.bundlePath.hasSuffix("en.lproj"))
        XCTAssertEqual(russian, "Вход")
        XCTAssertEqual(english, "Log In")
    }
}
