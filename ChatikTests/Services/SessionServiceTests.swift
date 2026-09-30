//
//  SessionServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class SessionServiceTests: XCTestCase {
    private let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)

    /// Создаёт сервис над моком хранилища и восстанавливает сессию.
    private func makeRestoredSUT(storedUser: User? = nil) async -> (SessionService, UserDefaultsServiceMock) {
        let defaults = UserDefaultsServiceMock(currentUser: storedUser)
        let sut = SessionService(userDefaultsService: defaults, localStorageCleaner: LocalStorageCleanerMock())
        await sut.restore()
        return (sut, defaults)
    }

    /// Кейс: сервис создан, `restore()` ещё не вызывался.
    /// Ожидание: `isRestored == false`, сессии нет.
    func test_init_isNotRestored() {
        let sut = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: user), localStorageCleaner: LocalStorageCleanerMock())

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

    /// Кейс: сессия открыта; приходит обновлённый профиль с аватаром.
    /// Ожидание: пользователь заменён в памяти и в хранилище — новый инстанс сервиса восстанавливает его с аватаром;
    /// флаг истечения не тронут.
    func test_update_whileLoggedIn_replacesUserInMemoryAndStorage() async {
        let (sut, defaults) = await makeRestoredSUT(storedUser: user)
        let updated = User(userId: user.userId, login: user.login, name: "Ivan Petrov", avatar: .stub)

        await sut.update(user: updated)

        let restored = SessionService(userDefaultsService: defaults, localStorageCleaner: LocalStorageCleanerMock())
        await restored.restore()
        XCTAssertEqual(sut.currentUser, updated)
        XCTAssertEqual(restored.currentUser, updated)
        XCTAssertFalse(sut.isExpired)
    }

    /// Кейс: сессии нет (пользователь вышел или она истекла); вызван `update(user:)`.
    /// Ожидание: ничего не происходит — сессия не открывается, хранилище пустое, флаг истечения сохранён.
    func test_update_whileLoggedOut_isNoop() async {
        let (sut, defaults) = await makeRestoredSUT(storedUser: user)
        await sut.expire()

        await sut.update(user: user)

        let stored = await defaults.currentUser()
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(stored)
        XCTAssertTrue(sut.isExpired)
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

    /// Кейс: выход пользователя.
    /// Ожидание: локальная БД очищена, и к моменту очистки пользователь ещё не сброшен —
    /// сначала очистка БД, затем сброс сессии.
    func test_end_clearsLocalStorageBeforeResettingUser() async {
        let cleaner = LocalStorageCleanerMock()
        let sut = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: user), localStorageCleaner: cleaner)
        await sut.restore()
        var isLoggedInDuringClear: Bool?
        cleaner.onClearAll = { isLoggedInDuringClear = sut.isLoggedIn }

        await sut.end()

        XCTAssertEqual(cleaner.clearAllCallCount, 1)
        XCTAssertEqual(isLoggedInDuringClear, true)
    }

    /// Кейс: выход пользователя, очистка локальной БД завершилась ошибкой.
    /// Ожидание: ошибка не блокирует выход — сессии нет в памяти и в хранилище.
    func test_end_clearFailure_stillEndsSession() async {
        let cleaner = LocalStorageCleanerMock()
        cleaner.stubbedError = CocoaError(.fileWriteUnknown)
        let defaults = UserDefaultsServiceMock(currentUser: user)
        let sut = SessionService(userDefaultsService: defaults, localStorageCleaner: cleaner)
        await sut.restore()

        await sut.end()

        let stored = await defaults.currentUser()
        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(stored)
    }

    /// Кейс: вход пользователя.
    /// Ожидание: локальная БД очищена до открытия сессии — данные, дописанные прежней сессией уже после её
    /// завершения, новому пользователю не достаются.
    func test_start_clearsLocalStorageBeforeOpeningSession() async {
        let cleaner = LocalStorageCleanerMock()
        let sut = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: nil), localStorageCleaner: cleaner)
        await sut.restore()
        var isLoggedInDuringClear: Bool?
        cleaner.onClearAll = { isLoggedInDuringClear = sut.isLoggedIn }

        await sut.start(user: user)

        XCTAssertEqual(cleaner.clearAllCallCount, 1)
        XCTAssertEqual(isLoggedInDuringClear, false)
        XCTAssertEqual(sut.currentUser, user)
    }

    /// Кейс: вход пользователя, очистка локальной БД завершилась ошибкой.
    /// Ожидание: ошибка не блокирует вход — сессия открыта и сохранена.
    func test_start_clearFailure_stillStartsSession() async {
        let cleaner = LocalStorageCleanerMock()
        cleaner.stubbedError = CocoaError(.fileWriteUnknown)
        let defaults = UserDefaultsServiceMock(currentUser: nil)
        let sut = SessionService(userDefaultsService: defaults, localStorageCleaner: cleaner)
        await sut.restore()

        await sut.start(user: user)

        let stored = await defaults.currentUser()
        XCTAssertEqual(sut.currentUser, user)
        XCTAssertEqual(stored, user)
    }

    /// Кейс: сервер вернул 2003 при активной сессии.
    /// Ожидание: локальная БД очищена так же, как при выходе пользователя.
    func test_expire_clearsLocalStorage() async {
        let cleaner = LocalStorageCleanerMock()
        let sut = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: user), localStorageCleaner: cleaner)
        await sut.restore()

        await sut.expire()

        XCTAssertEqual(cleaner.clearAllCallCount, 1)
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

    /// Кейс: сервер вернул 2003 при активной сессии; наблюдаем момент сброса `currentUser`.
    /// Ожидание: в момент сброса `currentUser` флаг `isExpired` уже поднят — экран авторизации,
    /// появившийся по этому изменению, увидит флаг в `onAppear`.
    func test_expire_raisesFlagBeforeClearingUser() async {
        let (sut, _) = await makeRestoredSUT(storedUser: user)
        let observed = ObservedFlag()
        withObservationTracking {
            _ = sut.currentUser
        } onChange: {
            MainActor.assumeIsolated { observed.value = sut.isExpired }
        }

        await sut.expire()

        XCTAssertEqual(observed.value, true)
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

/// Значение, снятое из `@Sendable`-замыкания `withObservationTracking`.
private final class ObservedFlag: @unchecked Sendable {
    var value: Bool?
}
