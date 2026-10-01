//
//  UserCacheServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class UserCacheServiceTests: XCTestCase {
    private var usersService: UsersServiceMock!
    private var userStorage: UserStorageServiceMock!
    private var clock: TestClock!
    private var sut: UserCacheService!

    private let ivan = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
    private let petr = User(userId: 2, login: "petr", name: "Petr", avatar: nil)
    private let renamedIvan = User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil)

    override func setUp() async throws {
        try await super.setUp()
        usersService = UsersServiceMock()
        userStorage = UserStorageServiceMock()
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_846_400))
        self.clock = clock
        sut = UserCacheService(usersService: usersService, userStorage: userStorage, now: { clock.now })
    }

    // MARK: - Отсутствующие пользователи

    /// Кейс: пользователя ещё не запрашивали.
    /// Ожидание: состояние `.pending` — экран показывает заглушку.
    func test_user_unknown_isPending() {
        XCTAssertEqual(sut.user(id: 1), .pending)
    }

    /// Кейс: пользователей нет ни в памяти, ни в БД; запрос к серверу задержан.
    /// Ожидание: `loadUsers` не завершается, пока не придёт ответ; после — найденные `.loaded` и сохранены в БД
    /// с текущим временем, ненайденные — `.notFound`.
    func test_loadUsers_missing_waitsForFetchAndStoresResult() async {
        let gate = Gate()
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan], notFoundIds: [999]))]
        usersService.onRequest = { await gate.wait() }
        var isLoaded = false

        let load = Task {
            await sut.loadUsers(ids: [1, 999])
            isLoaded = true
        }
        await waitUntil { gate.isWaiting }
        XCTAssertFalse(isLoaded)
        gate.open()
        await load.value

        XCTAssertEqual(usersService.batchRequests, [[1, 999]])
        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
        XCTAssertEqual(sut.user(id: 999), .notFound)
        XCTAssertEqual(userStorage.savedBatches.map(\.users), [[ivan]])
        XCTAssertEqual(userStorage.savedBatches.map(\.cachedAt), [clock.now])
    }

    /// Кейс: отсутствующего пользователя упомянули второй раз, пока первый запрос за ним идёт.
    /// Ожидание: второго запроса нет, но второй вызов тоже ждёт ответа первого — возвращается с загруженным пользователем.
    func test_loadUsers_missingAlreadyRequested_waitsForSameRequest() async {
        let gate = Gate()
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan], notFoundIds: []))]
        usersService.onRequest = { await gate.wait() }

        var isSecondFinished = false

        let first = Task { await sut.loadUsers(ids: [1]) }
        await waitUntil { gate.isWaiting }
        let second = Task {
            await sut.loadUsers(ids: [1])
            isSecondFinished = true
            return sut.user(id: 1)
        }
        // Второй вызов прочитал БД и дошёл до идущего запроса; даём ему время вернуться, если он не ждёт.
        await waitUntil { [unowned self] in userStorage.findStoredCallCount == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(isSecondFinished)
        gate.open()
        await first.value
        let stateAfterSecond = await second.value

        XCTAssertEqual(usersService.batchRequests, [[1]])
        XCTAssertEqual(stateAfterSecond, .loaded(ivan))
    }

    /// Кейс: запрос отсутствующего пользователя не удался, затем пользователь упомянут снова.
    /// Ожидание: первый вызов завершается без ошибки, пользователь `.pending`; второй вызов повторяет запрос.
    func test_loadUsers_requestFailed_retriesOnNextCall() async {
        usersService.stubbedBatches = [
            .failure(NetworkError.transport(URLError(.notConnectedToInternet))),
            .success(UsersBatch(users: [ivan], notFoundIds: [])),
        ]

        await sut.loadUsers(ids: [1])
        XCTAssertEqual(sut.user(id: 1), .pending)
        await sut.loadUsers(ids: [1])

        XCTAssertEqual(usersService.batchRequests, [[1], [1]])
        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
    }

    /// Кейс: сервер сообщил, что пользователя нет, затем его упомянули снова.
    /// Ожидание: повторно он не запрашивается и остаётся `.notFound`.
    func test_loadUsers_notFound_isNotRequestedAgain() async {
        usersService.stubbedBatches = [.success(UsersBatch(users: [], notFoundIds: [999]))]
        await sut.loadUsers(ids: [999])

        await sut.loadUsers(ids: [999])

        XCTAssertEqual(usersService.batchRequests, [[999]])
        XCTAssertEqual(sut.user(id: 999), .notFound)
    }

    // MARK: - Свежие и устаревшие

    /// Кейс: пользователь загружен, через 2 минуты 59 секунд упомянут снова.
    /// Ожидание: он ещё свежий — повторного запроса нет.
    func test_loadUsers_freshInMemory_doesNotRequest() async {
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan], notFoundIds: []))]
        await sut.loadUsers(ids: [1])
        clock.advance(by: UserCacheService.freshnessInterval - 1)

        await sut.loadUsers(ids: [1])

        XCTAssertEqual(usersService.batchRequests, [[1]])
    }

    /// Кейс: пользователь загружен, через 3 минуты упомянут снова; повторный запрос задержан.
    /// Ожидание: `loadUsers` возвращается, не дожидаясь запроса, пользователь пока прежний; после ответа — обновлён.
    func test_loadUsers_staleInMemory_refreshesInBackground() async {
        let gate = Gate()
        usersService.stubbedBatches = [
            .success(UsersBatch(users: [ivan], notFoundIds: [])),
            .success(UsersBatch(users: [renamedIvan], notFoundIds: [])),
        ]
        await sut.loadUsers(ids: [1])
        clock.advance(by: UserCacheService.freshnessInterval)
        usersService.onRequest = { await gate.wait() }

        await sut.loadUsers(ids: [1])
        await waitUntil { gate.isWaiting }
        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
        gate.open()
        await waitUntil { [unowned self] in sut.user(id: 1) == .loaded(renamedIvan) }

        XCTAssertEqual(usersService.batchRequests, [[1], [1]])
    }

    /// Кейс: устаревшего пользователя упомянули дважды, пока его фоновое обновление идёт.
    /// Ожидание: обновление запрошено один раз.
    func test_loadUsers_staleAlreadyRefreshing_doesNotRequestAgain() async {
        let gate = Gate()
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: .distantPast)
        usersService.stubbedBatches = [.success(UsersBatch(users: [renamedIvan], notFoundIds: []))]
        usersService.onRequest = { await gate.wait() }

        await sut.loadUsers(ids: [1])
        await waitUntil { gate.isWaiting }
        await sut.loadUsers(ids: [1])
        gate.open()
        await waitUntil { [unowned self] in sut.user(id: 1) == .loaded(renamedIvan) }

        XCTAssertEqual(usersService.batchRequests, [[1]])
    }

    /// Кейс: пользователь есть в БД, получен меньше 3 минут назад.
    /// Ожидание: он подставлен из БД без запроса к серверу.
    func test_loadUsers_freshInStorage_usesStoredWithoutRequest() async {
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: clock.now - 60)

        await sut.loadUsers(ids: [1])

        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
        XCTAssertTrue(usersService.batchRequests.isEmpty)
    }

    /// Кейс: пользователь есть в БД, получен давно (например, в прошлом запуске); запрос задержан.
    /// Ожидание: `loadUsers` возвращается сразу с пользователем из БД, обновление идёт в фоне.
    func test_loadUsers_staleInStorage_returnsStoredAndRefreshesInBackground() async {
        let gate = Gate()
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: clock.now - UserCacheService.freshnessInterval)
        usersService.stubbedBatches = [.success(UsersBatch(users: [renamedIvan], notFoundIds: []))]
        usersService.onRequest = { await gate.wait() }

        await sut.loadUsers(ids: [1])
        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
        await waitUntil { gate.isWaiting }
        gate.open()

        await waitUntil { [unowned self] in sut.user(id: 1) == .loaded(renamedIvan) }
    }

    /// Кейс: в одном action устаревший пользователь (в БД) и отсутствующий; запрос устаревшего задержан.
    /// Ожидание: устаревший и отсутствующий запрошены разными запросами; `loadUsers` ждёт только отсутствующего.
    func test_loadUsers_staleAndMissing_waitsOnlyForMissing() async {
        let gate = Gate()
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: .distantPast)
        usersService.stubbedBatches = [
            .success(UsersBatch(users: [renamedIvan], notFoundIds: [])),
            .success(UsersBatch(users: [petr], notFoundIds: [])),
        ]
        usersService.onRequest = { [unowned self] in
            guard usersService.batchRequests.count == 1 else { return }
            await gate.wait()
        }

        await sut.loadUsers(ids: [1, 2])

        XCTAssertEqual(usersService.batchRequests, [[1], [2]])
        XCTAssertEqual(sut.user(id: 2), .loaded(petr))
        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
        gate.open()
        await waitUntil { [unowned self] in sut.user(id: 1) == .loaded(renamedIvan) }
    }

    /// Кейс: пользователь был в БД, а сервер при обновлении сообщил, что его больше нет.
    /// Ожидание: состояние `.notFound`, а не устаревшие данные из БД.
    func test_loadUsers_storedUserNotFoundOnServer_becomesNotFound() async {
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: .distantPast)
        usersService.stubbedBatches = [.success(UsersBatch(users: [], notFoundIds: [1]))]

        await sut.loadUsers(ids: [1])

        await waitUntil { [unowned self] in sut.user(id: 1) == .notFound }
    }

    // MARK: - Потокобезопасность

    /// Кейс: 50 одновременных вызовов `loadUsers` из фоновых задач, запрос к серверу задержан, пока они собираются.
    /// Ожидание: уходит один запрос, и каждый вызывающий после возврата видит загруженных пользователей.
    func test_loadUsers_concurrentCallsFromBackground_requestOnceAndSeeLoaded() async {
        let gate = Gate()
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan, petr], notFoundIds: []))]
        usersService.onRequest = { await gate.wait() }
        let cache: UserCacheService = sut

        let states = await withTaskGroup(of: [CachedUser].self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await cache.loadUsers(ids: [1, 2])
                    return [await cache.user(id: 1), await cache.user(id: 2)]
                }
            }
            await waitUntil { gate.isWaiting }
            gate.open()
            return await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(usersService.batchRequests, [[1, 2]])
        XCTAssertEqual(states.count, 50)
        XCTAssertTrue(states.allSatisfy { $0 == [.loaded(ivan), .loaded(petr)] })
    }

    /// Кейс: пока один вызов читает пользователя из БД, другой успевает обновить его с сервера —
    /// сервер сообщает, что пользователя больше нет.
    /// Ожидание: опоздавшее чтение БД не возвращает удалённого пользователя — он остаётся `.notFound`.
    func test_loadUsers_lateStorageRead_doesNotResurrectNotFoundUser() async {
        let gate = Gate()
        userStorage.storedUsers[1] = StoredUser(user: ivan, cachedAt: .distantPast)
        usersService.stubbedBatches = [.success(UsersBatch(users: [], notFoundIds: [1]))]
        userStorage.onFindStored = { callIndex in
            guard callIndex == 0 else { return }
            await gate.wait()
        }

        let slowRead = Task { await sut.loadUsers(ids: [1]) }
        await waitUntil { gate.isWaiting }
        await sut.loadUsers(ids: [1])
        await waitUntil { [unowned self] in sut.user(id: 1) == .notFound }
        gate.open()
        await slowRead.value

        XCTAssertEqual(sut.user(id: 1), .notFound)
    }

    // MARK: - Пачки и ошибки

    /// Кейс: упомянуто 250 отсутствующих пользователей — больше, чем сервер принимает за один запрос.
    /// Ожидание: запросы пачками по 100, 100 и 50 id без потерь и повторов; `loadUsers` ждёт все.
    func test_loadUsers_manyIds_requestsInBatchesOfLimit() async {
        let ids = Array(1...250)
        usersService.stubbedBatches = Array(repeating: .success(UsersBatch(users: [], notFoundIds: [])), count: 3)

        await sut.loadUsers(ids: ids)

        XCTAssertEqual(usersService.batchRequests.map(\.count), [100, 100, 50])
        XCTAssertEqual(usersService.batchRequests.flatMap { $0 }, ids)
    }

    /// Кейс: в списке id есть повторы.
    /// Ожидание: каждый id запрошен один раз, в порядке первого появления.
    func test_loadUsers_duplicateIds_requestedOnce() async {
        usersService.stubbedBatches = [.success(UsersBatch(users: [], notFoundIds: []))]

        await sut.loadUsers(ids: [2, 1, 2, 1])

        XCTAssertEqual(usersService.batchRequests, [[2, 1]])
    }

    /// Кейс: чтение из БД не удалось.
    /// Ожидание: ошибка не мешает загрузить пользователя с сервера.
    func test_loadUsers_storageReadError_stillFetchesFromServer() async {
        userStorage.stubbedFindError = NSError(domain: "test", code: 1)
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan], notFoundIds: []))]

        await sut.loadUsers(ids: [1])

        XCTAssertEqual(sut.user(id: 1), .loaded(ivan))
    }

    /// Кейс: экран читает пользователя, затем пользователь загружается.
    /// Ожидание: Observation сообщает об изменении — экран перерисуется без запроса.
    func test_user_loaded_notifiesObservers() async {
        usersService.stubbedBatches = [.success(UsersBatch(users: [ivan], notFoundIds: []))]
        let changed = ChangeFlag()
        withObservationTracking { _ = sut.user(id: 1) } onChange: { changed.isSet = true }

        await sut.loadUsers(ids: [1])

        XCTAssertTrue(changed.isSet)
    }
}

/// Флаг срабатывания `onChange` из `withObservationTracking`.
private final class ChangeFlag: @unchecked Sendable {
    var isSet = false
}
