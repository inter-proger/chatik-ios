//
//  SessionServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class SessionServiceTests: XCTestCase {
    private let user = AuthUser(userId: 1, name: "Ivan")

    /// Создаёт сервис над моком хранилища и восстанавливает сессию.
    private func makeRestoredSUT(storedUser: AuthUser? = nil) async -> (SessionService, UserDefaultsServiceMock) {
        let defaults = UserDefaultsServiceMock(currentUser: storedUser)
        let sut = SessionService(userDefaultsService: defaults)
        await sut.restore()
        return (sut, defaults)
    }

    /// Кейс: сервис создан, `restore()` ещё не вызывался.
    /// Ожидание: `isRestored == false`, сессии нет.
    func test_init_isNotRestored() {
        let sut = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: user))

        XCTAssertFalse(sut.isRestored)
        XCTAssertFalse(sut.isLoggedIn)
    }

    /// Кейс: в хранилище есть сохранённый пользователь / нет пользователя; вызван `restore()`.
    /// Ожидание: сессия восстановлена из хранилища, `isRestored == true`.
    func test_restore_loadsSessionFromStorage() async {
        let (withUser, _) = await makeRestoredSUT(storedUser: user)
        let (withoutUser, _) = await makeRestoredSUT()

        XCTAssertTrue(withUser.isRestored)
        XCTAssertEqual(withUser.currentUser, user)
        XCTAssertTrue(withoutUser.isRestored)
        XCTAssertFalse(withoutUser.isLoggedIn)
    }

    /// Кейс: повторный `restore()` после того, как сессия уже открыта и хранилище изменилось извне.
    /// Ожидание: повторный вызов ничего не делает — текущая сессия не затирается.
    func test_restore_secondCall_isNoop() async {
        let (sut, defaults) = await makeRestoredSUT()
        await sut.start(user: user)
        await defaults.setCurrentUser(nil)

        await sut.restore()

        XCTAssertEqual(sut.currentUser, user)
    }

    /// Кейс: открытие сессии после входа.
    /// Ожидание: пользователь доступен в памяти и записан в хранилище, флаг истечения сброшен.
    func test_start_storesUserAndResetsExpiration() async {
        let (sut, defaults) = await makeRestoredSUT(storedUser: user)
        await sut.expire()

        await sut.start(user: user)

        let stored = await defaults.currentUser()
        XCTAssertEqual(sut.currentUser, user)
        XCTAssertEqual(stored, user)
        XCTAssertFalse(sut.isExpired)
    }

    /// Кейс: выход пользователя.
    /// Ожидание: сессии нет в памяти и в хранилище, флаг истечения не поднят.
    func test_end_clearsUserWithoutExpirationFlag() async {
        let (sut, defaults) = await makeRestoredSUT(storedUser: user)

        await sut.end()

        let stored = await defaults.currentUser()
        XCTAssertNil(sut.currentUser)
        XCTAssertNil(stored)
        XCTAssertFalse(sut.isExpired)
    }

    /// Кейс: сервер вернул 2003 при активной сессии.
    /// Ожидание: сессия завершена, поднят `isExpired`; после `acknowledgeExpiration` флаг сброшен.
    func test_expire_whileLoggedIn_endsSessionAndRaisesFlag() async {
        let (sut, defaults) = await makeRestoredSUT(storedUser: user)

        await sut.expire()

        let stored = await defaults.currentUser()
        XCTAssertNil(sut.currentUser)
        XCTAssertNil(stored)
        XCTAssertTrue(sut.isExpired)

        sut.acknowledgeExpiration()
        XCTAssertFalse(sut.isExpired)
    }

    /// Кейс: сервер вернул 2003, когда сессии уже нет (например, после явного выхода).
    /// Ожидание: ничего не происходит, флаг истечения не поднимается.
    func test_expire_whileLoggedOut_isNoop() async {
        let (sut, _) = await makeRestoredSUT()

        await sut.expire()

        XCTAssertFalse(sut.isExpired)
        XCTAssertFalse(sut.isLoggedIn)
    }
}
