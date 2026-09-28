//
//  ConversationServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: ConversationService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = ConversationService(networkService: networkService)
    }

    /// Кейс: создание личной переписки с пользователем.
    /// Ожидание: POST /conversation/createSingle с `userId`, наружу отдана переписка из поля `conversation`.
    func test_createSingle_requestsEndpointAndUnwrapsConversation() async throws {
        let expected = Conversation.singleStub
        networkService.stubbedResult = .success(ConversationResponse(conversation: expected))

        let conversation = try await sut.createSingle(userId: 2)

        XCTAssertEqual(conversation, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/conversation/createSingle")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["userId": "2"])
    }

    /// Кейс: сервер вернул групповую переписку — с названием и аватаром.
    /// Ожидание: наружу отданы все поля, включая название и аватар.
    func test_createSingle_unwrapsGroupConversationFields() async throws {
        networkService.stubbedResult = .success(ConversationResponse(conversation: .groupStub))

        let conversation = try await sut.createSingle(userId: 3)

        XCTAssertEqual(conversation, .groupStub)
        XCTAssertEqual(conversation.name, "Команда")
        XCTAssertEqual(conversation.avatar, .stub)
    }

    /// Кейс: сервер вернул бизнес-ошибку (переписка с самим собой).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_createSingle_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.conversationWithSelf))

        do {
            _ = try await sut.createSingle(userId: 1)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 5001))
        }
    }
}
