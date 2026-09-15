//
//  AppRouterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AppRouterTests: XCTestCase {
    private let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)

    /// Создаёт роутер над сессией с заданным сохранённым пользователем и без задержки splash.
    private func makeSUT(
        storedUser: User? = nil,
        storedLanguage: AppLanguage? = nil,
        minimumSplashDuration: Duration = .zero
    ) -> AppRouter {
        let defaults = UserDefaultsServiceMock(currentUser: storedUser, language: storedLanguage)
        return AppRouter(
            sessionService: SessionService(userDefaultsService: defaults),
            localizationService: LocalizationService(userDefaultsService: defaults, systemLanguage: .ru),
            minimumSplashDuration: minimumSplashDuration
        )
    }

    /// Кейс: приложение запустилось, `restoreSession()` ещё не завершился.
    /// Ожидание: корневой экран — splash.
    func test_root_beforeRestore_isSplash() {
        let sut = makeSUT(storedUser: user)

        XCTAssertEqual(sut.root, .splash)
    }

    /// Кейс: после `restoreSession()` в хранилище нет сессии / есть сессия.
    /// Ожидание: корень — авторизация / список чатов соответственно.
    func test_restoreSession_setsRootFromStorage() async {
        let withoutSession = makeSUT()
        let withSession = makeSUT(storedUser: user)

        await withoutSession.restoreSession()
        await withSession.restoreSession()

        XCTAssertEqual(withoutSession.root, .auth)
        XCTAssertEqual(withSession.root, .chats)
    }

    /// Кейс: задано минимальное время показа splash, сессия восстанавливается мгновенно.
    /// Ожидание: `restoreSession()` завершается не раньше этого времени; до завершения корень — splash.
    func test_restoreSession_holdsSplashForMinimumDuration() async {
        let sut = makeSUT(minimumSplashDuration: .milliseconds(150))
        let start = ContinuousClock.now

        await sut.restoreSession()

        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(150))
        XCTAssertEqual(sut.root, .auth)
    }

    /// Кейс: сессия открывается, завершается пользователем, открывается и истекает по 2003.
    /// Ожидание: корень следует за состоянием сессии: auth → chats → auth → chats → auth.
    func test_root_followsSessionChanges() async {
        let defaults = UserDefaultsServiceMock()
        let session = SessionService(userDefaultsService: defaults)
        let sut = AppRouter(
            sessionService: session,
            localizationService: LocalizationService(userDefaultsService: defaults, systemLanguage: .ru),
            minimumSplashDuration: .zero
        )
        await sut.restoreSession()

        await session.start(user: user)
        XCTAssertEqual(sut.root, .chats)

        await session.end()
        XCTAssertEqual(sut.root, .auth)

        await session.start(user: user)
        XCTAssertEqual(sut.root, .chats)

        await session.expire()
        XCTAssertEqual(sut.root, .auth)
    }

    /// Кейс: пользователь ранее выбрал английский; системный язык — русский.
    /// Ожидание: после `restoreSession()` локаль приложения — английская.
    func test_restoreSession_restoresSavedLanguage() async {
        let sut = makeSUT(storedLanguage: .en)
        XCTAssertEqual(sut.locale.identifier, "ru")

        await sut.restoreSession()

        XCTAssertEqual(sut.locale.identifier, "en")
    }
}
