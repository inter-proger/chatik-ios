//
//  AuthServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AuthServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var log: EventLog!
    private var sut: AuthService!

    override func setUp() async throws {
        try await super.setUp()
        networkService = NetworkServiceMock()
        log = EventLog()
        sut = AuthService(networkService: networkService)
    }

    /// Кейс: успешная регистрация.
    /// Ожидание: POST /auth/signup с login/password/name, возвращён пользователь из ответа.
    func test_signup_requestsSignupEndpointAndReturnsUser() async throws {
        let expected = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
        networkService.stubbedResult = .success(expected)

        let user = try await sut.signup(login: "ivan", password: "Password1", name: "Ivan")

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/auth/signup")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["login": "ivan", "password": "Password1", "name": "Ivan"])
    }

    /// Кейс: успешный вход.
    /// Ожидание: запрос на /auth/login с login/password, возвращён пользователь из ответа.
    func test_login_requestsLoginEndpointAndReturnsUser() async throws {
        let expected = User(userId: 7, login: "ivan", name: "Ivan", avatar: nil)
        networkService.stubbedResult = .success(expected)

        let user = try await sut.login(login: "ivan", password: "Password1")

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/auth/login")
        XCTAssertEqual(endpoint.parameters, ["login": "ivan", "password": "Password1"])
    }

    /// Кейс: сервер вернул бизнес-ошибку при входе (неверный пароль).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_login_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: 2002))

        do {
            _ = try await sut.login(login: "ivan", password: "wrong")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 2002))
        }
    }

    // MARK: - Выход

    /// Кейс: выход; сервер отвечает успехом / «не авторизован» / транспортной ошибкой.
    /// Ожидание: при любом ответе ушёл запрос на /auth/logout, cookie сессии очищены, наблюдатель узнал о выходе
    /// по кнопке.
    func test_logout_anyResponse_clearsCookiesAndNotifiesObservers() async {
        let results: [Result<Any, Error>] = [
            .success(EmptyResponse()),
            .failure(NetworkError.api(code: NetworkError.Code.unauthorized)),
            .failure(NetworkError.transport(URLError(.notConnectedToInternet))),
        ]

        for result in results {
            let caseNetworkService = NetworkServiceMock()
            caseNetworkService.stubbedResult = result
            let caseLog = EventLog()
            let observer = AuthServiceObserverMock(log: caseLog)
            let caseSUT = AuthService(networkService: caseNetworkService)
            caseSUT.addObserver(observer)

            await caseSUT.logout()

            XCTAssertEqual(caseNetworkService.requestedEndpoints.map(\.path), ["/auth/logout"], "\(result)")
            XCTAssertEqual(caseNetworkService.clearSessionCookiesCallCount, 1, "\(result)")
            XCTAssertEqual(caseLog.events, ["observer.willLogout", "observer.didLogout"], "\(result)")
            XCTAssertEqual(observer.reasons, [.userInitiated], "\(result)")
        }
    }

    /// Кейс: выход с двумя наблюдателями.
    /// Ожидание: все наблюдатели в порядке подписки узнают о начале выхода до запроса, а о завершении — после него
    /// и после очистки cookie.
    func test_logout_notifiesObserversAroundRequestInSubscriptionOrder() async {
        let first = AuthServiceObserverMock(name: "first", log: log)
        let second = AuthServiceObserverMock(name: "second", log: log)
        sut.addObserver(first)
        sut.addObserver(second)
        networkService.stubbedResult = .success(EmptyResponse())
        networkService.onRequest = { [unowned self] in log.events.append("request") }

        await sut.logout()

        XCTAssertEqual(log.events, ["first.willLogout", "second.willLogout", "request", "first.didLogout", "second.didLogout"])
    }

    /// Кейс: наблюдатель подписан дважды.
    /// Ожидание: каждое уведомление он получает один раз.
    func test_addObserver_twice_notifiesOnce() async {
        let observer = AuthServiceObserverMock(log: log)
        sut.addObserver(observer)
        sut.addObserver(observer)
        networkService.stubbedResult = .success(EmptyResponse())

        await sut.logout()

        XCTAssertEqual(log.events, ["observer.willLogout", "observer.didLogout"])
    }

    /// Кейс: наблюдатель отписан до выхода.
    /// Ожидание: уведомлений он не получает.
    func test_removeObserver_stopsNotifications() async {
        let observer = AuthServiceObserverMock(log: log)
        sut.addObserver(observer)
        sut.removeObserver(observer)
        networkService.stubbedResult = .success(EmptyResponse())

        await sut.logout()

        XCTAssertTrue(log.events.isEmpty)
    }

    /// Кейс: наблюдатель уничтожен, не отписавшись.
    /// Ожидание: сервис его не удерживает, выход проходит без уведомлений.
    func test_addObserver_holdsObserverWeakly() async {
        var observer: AuthServiceObserverMock? = AuthServiceObserverMock(log: log)
        weak let weakObserver = observer
        sut.addObserver(observer!)
        observer = nil
        networkService.stubbedResult = .success(EmptyResponse())

        await sut.logout()

        XCTAssertNil(weakObserver)
        XCTAssertTrue(log.events.isEmpty)
    }

    /// Кейс: во время запроса выхода выход вызван ещё раз.
    /// Ожидание: повторный выход сразу возвращается — запрос один, каждое уведомление наблюдатель получил один раз.
    func test_logout_whileLoggingOut_isIgnored() async {
        let observer = AuthServiceObserverMock(log: log)
        sut.addObserver(observer)
        networkService.stubbedResult = .success(EmptyResponse())
        networkService.onRequest = { [unowned self] in await sut.logout() }

        await sut.logout()

        XCTAssertEqual(networkService.requestedEndpoints.count, 1)
        XCTAssertEqual(log.events, ["observer.willLogout", "observer.didLogout"])
    }

    // MARK: - Истечение сессии

    /// Кейс: сессия истекла на сервере.
    /// Ожидание: запроса нет, cookie очищены, наблюдатель прошёл обе фазы и узнал причину — истечение.
    func test_expireSession_notifiesObserversWithoutRequest() async {
        let observer = AuthServiceObserverMock(log: log)
        sut.addObserver(observer)

        sut.expireSession()
        await yieldUntil { observer.reasons == [.sessionExpired] }

        XCTAssertTrue(networkService.requestedEndpoints.isEmpty)
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 1)
        XCTAssertEqual(log.events, ["observer.willLogout", "observer.didLogout"])
    }

    /// Кейс: во время выхода по кнопке пришло истечение сессии (2003 от отменяемого запроса).
    /// Ожидание: истечение ничего не делает — наблюдатель получил только уведомления выхода по кнопке.
    func test_expireSession_whileLoggingOut_isIgnored() async {
        let observer = AuthServiceObserverMock(log: log)
        sut.addObserver(observer)
        networkService.stubbedResult = .success(EmptyResponse())
        networkService.onRequest = { [unowned self] in
            sut.expireSession()
            await Task.yield()
        }

        await sut.logout()
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(log.events, ["observer.willLogout", "observer.didLogout"])
        XCTAssertEqual(observer.reasons, [.userInitiated])
    }
}
