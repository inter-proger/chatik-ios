//
//  AuthServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AuthServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: AuthService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = AuthService(networkService: networkService)
    }

    func test_signup_requestsSignupEndpointAndReturnsUser() async throws {
        let expected = AuthUser(userId: 1, name: "Ivan")
        networkService.stubbedResult = .success(expected)

        let user = try await sut.signup(login: "ivan", password: "Password1", name: "Ivan")

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/auth/signup")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["login": "ivan", "password": "Password1", "name": "Ivan"])
    }

    func test_login_requestsLoginEndpointAndReturnsUser() async throws {
        let expected = AuthUser(userId: 7, name: "Ivan")
        networkService.stubbedResult = .success(expected)

        let user = try await sut.login(login: "ivan", password: "Password1")

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/auth/login")
        XCTAssertEqual(endpoint.parameters, ["login": "ivan", "password": "Password1"])
    }

    func test_login_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: 2002))

        do {
            _ = try await sut.login(login: "ivan", password: "wrong")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 2002))
        }
    }

    func test_logout_success_clearsSessionCookies() async throws {
        networkService.stubbedResult = .success(EmptyResponse())

        try await sut.logout()

        XCTAssertEqual(networkService.requestedEndpoints.first?.path, "/auth/logout")
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 1)
    }

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

    func test_logout_transportError_keepsCookies() async {
        networkService.stubbedResult = .failure(NetworkError.transport("offline"))

        do {
            try await sut.logout()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .transport("offline"))
        }
        XCTAssertEqual(networkService.clearSessionCookiesCallCount, 0)
    }
}
