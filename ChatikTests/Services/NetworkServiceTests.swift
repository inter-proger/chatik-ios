//
//  NetworkServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class NetworkServiceTests: XCTestCase {
    private let baseURL = URL(string: "http://localhost:8080")!
    private var cookieStorage: HTTPCookieStorage!
    private var sut: NetworkService!

    override func setUp() {
        super.setUp()
        cookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "ChatikTests.\(UUID().uuidString)")
        sut = NetworkService(session: URLProtocolStub.makeSession(), baseURL: baseURL, cookieStorage: cookieStorage)
    }

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        sut = nil
        cookieStorage = nil
        super.tearDown()
    }

    // MARK: - Request building

    func test_post_sendsFormURLEncodedBodyToCorrectPath() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{"userId":1,"name":"Ivan"}}"#)

        let _: AuthUser = try await sut.request(AuthEndpoint.login(login: "ivan_1", password: "Pass word&1"))

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/auth/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.bodyString, "login=ivan_1&password=Pass+word%261")
    }

    func test_get_putsParametersIntoQueryAndAppliesHeaders() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{}}"#)
        let endpoint = TestEndpoint(path: "/items", method: .get, parameters: ["page": "2", "q": "a b"], headers: ["X-Test": "1"])

        let _: EmptyResponse = try await sut.request(endpoint)

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/items?page=2&q=a%20b")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
        XCTAssertNil(request.bodyString)
    }

    // MARK: - Response handling

    func test_successResponse_returnsDecodedPayload() async throws {
        _ = stub(status: 200, json: #"{"status":1,"response":{"userId":42,"name":"Ivan Petrov"}}"#)

        let user: AuthUser = try await sut.request(AuthEndpoint.logout)

        XCTAssertEqual(user, AuthUser(userId: 42, name: "Ivan Petrov"))
    }

    func test_errorStatus_throwsApiErrorWithCode() async {
        _ = stub(status: 200, json: #"{"status":0,"errorCode":2002}"#)

        await assertThrows(NetworkError.api(code: 2002)) {
            let _: AuthUser = try await sut.request(AuthEndpoint.logout)
        }
    }

    func test_successStatusWithoutResponse_throwsMissingResponse() async {
        _ = stub(status: 200, json: #"{"status":1}"#)

        await assertThrows(NetworkError.missingResponse) {
            let _: AuthUser = try await sut.request(AuthEndpoint.logout)
        }
    }

    func test_non2xxHttpStatus_throwsInvalidResponse() async {
        _ = stub(status: 500, json: "")

        await assertThrows(NetworkError.invalidResponse(statusCode: 500)) {
            let _: AuthUser = try await sut.request(AuthEndpoint.logout)
        }
    }

    func test_malformedJson_throwsDecodingError() async {
        _ = stub(status: 200, json: "not json")

        do {
            let _: AuthUser = try await sut.request(AuthEndpoint.logout)
            XCTFail("Expected decoding error")
        } catch NetworkError.decoding {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_transportFailure_throwsTransportError() async {
        URLProtocolStub.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            let _: AuthUser = try await sut.request(AuthEndpoint.logout)
            XCTFail("Expected transport error")
        } catch NetworkError.transport {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Cookies

    func test_clearSessionCookies_removesCookiesForBaseURL() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "PHPSESSID", .value: "abc", .domain: "localhost", .path: "/"
        ]))
        cookieStorage.setCookie(cookie)
        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count, 1)

        sut.clearSessionCookies()

        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count ?? 0, 0)
    }

    // MARK: - Helpers

    /// Подставляет ответ сервера и возвращает контейнер с перехваченным запросом.
    private func stub(status: Int, json: String) -> CapturedRequest {
        let captured = CapturedRequest()
        URLProtocolStub.requestHandler = { request in
            captured.request = request
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        return captured
    }

    /// Проверяет, что замыкание бросает ровно ожидаемую `NetworkError`.
    private func assertThrows(
        _ expected: NetworkError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as NetworkError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class CapturedRequest: @unchecked Sendable {
    var request: URLRequest?
}

private struct TestEndpoint: Endpoint {
    let path: String
    let method: HTTPMethod
    let parameters: [String: String]
    let headers: [String: String]?
}
