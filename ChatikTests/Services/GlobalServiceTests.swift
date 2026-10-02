//
//  GlobalServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class GlobalServiceTests: XCTestCase {
    private let info = WebsocketConnectInfo(url: URL(string: "wss://example.com/ws")!, token: "token", expiresIn: 120)
    private var networkService: NetworkServiceMock!
    private var sut: GlobalService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = GlobalService(networkService: networkService)
    }

    /// Кейс: авторизованный пользователь вызывает `/global/start`.
    /// Ожидание: GET /global/start без параметров, наружу отданы данные подключения.
    func test_start_authorized_returnsConnectInfo() async throws {
        networkService.stubbedResult = .success(GlobalStartResponse(websocketConnectInfo: info))

        let result = try await sut.start()

        XCTAssertEqual(result, info)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/global/start")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: `/global/start` вернул `websocketConnectInfo: null` — пользователь не авторизован.
    /// Ожидание: наружу отдан `nil`, ошибки нет.
    func test_start_anonymous_returnsNil() async throws {
        networkService.stubbedResult = .success(GlobalStartResponse(websocketConnectInfo: nil))

        let result = try await sut.start()

        XCTAssertNil(result)
    }

    /// Кейс: запрос нового токена для переподключения.
    /// Ожидание: GET /global/getWebsocketToken, наружу отданы данные подключения.
    func test_fetchWebsocketToken_returnsConnectInfo() async throws {
        networkService.stubbedResult = .success(WebsocketTokenResponse(websocketConnectInfo: info))

        let result = try await sut.fetchWebsocketToken()

        XCTAssertEqual(result, info)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/global/getWebsocketToken")
        XCTAssertEqual(endpoint.method, .get)
    }

    /// Кейс: ответ `/global/start` из документации, с неизвестным полем и с `null`.
    /// Ожидание: оба разобраны; неизвестное поле пропущено.
    func test_decodeGlobalStartResponse_ignoresUnknownFields() throws {
        let authorized = """
        { "websocketConnectInfo": { "url": "wss://example.com/ws", "token": "token", "expiresIn": 120 }, "future": 1 }
        """
        let anonymous = #"{ "websocketConnectInfo": null }"#

        let decodedAuthorized = try JSONDecoder().decode(GlobalStartResponse.self, from: Data(authorized.utf8))
        let decodedAnonymous = try JSONDecoder().decode(GlobalStartResponse.self, from: Data(anonymous.utf8))

        XCTAssertEqual(decodedAuthorized.websocketConnectInfo, info)
        XCTAssertNil(decodedAnonymous.websocketConnectInfo)
    }
}
