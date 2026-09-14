//
//  AppRouterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AppRouterTests: XCTestCase {
    private let user = AuthUser(userId: 1, name: "Ivan")

    /// Создаёт роутер над сессией с заданным сохранённым пользователем и без задержки splash.
    private func makeSUT(storedUser: AuthUser? = nil, minimumSplashDuration: Duration = .zero) -> AppRouter {
        AppRouter(
            sessionService: SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: storedUser)),
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
        let session = SessionService(userDefaultsService: UserDefaultsServiceMock())
        let sut = AppRouter(sessionService: session, minimumSplashDuration: .zero)
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
}
