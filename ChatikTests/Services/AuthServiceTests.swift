//
//  AuthServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class AuthServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: AuthService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
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

    /// Кейс: успешный выход.
    /// Ожидание: запрос на /auth/logout и однократная очистка cookie сессии.
    func test_logout_success_clearsSessionCookies() async throws {
        networkService.stubbedResult = .success(EmptyResponse())

        try await sut.logout()

        XCTAssertEqual(networkService.requestedEndpoints.first?.path, "/auth/logout")
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 1)
    }

    /// Кейс: сервер ответил «не авторизован» при выходе (сессия уже недействительна).
    /// Ожидание: cookie сессии очищены локально, ошибка проброшена наружу.
    func test_logout_unauthorized_clearsCookiesAndRethrows() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: 2003))

        do {
            try await sut.logout()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 2003))
        }
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 1)
    }

    /// Кейс: сетевая ошибка при выходе (нет соединения).
    /// Ожидание: cookie сессии не тронуты, чтобы повторить выход позже; ошибка проброшена.
    func test_logout_transportError_keepsCookies() async {
        networkService.stubbedResult = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        do {
            try await sut.logout()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .transport(URLError(.notConnectedToInternet)))
        }
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 0)
    }
}
