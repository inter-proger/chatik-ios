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
        XCTAssertEqual(endpoint.path, "/conversations/createSingle")
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

    /// Кейс: запрос первой страницы списка переписок без явных параметров.
    /// Ожидание: GET /conversations/getList без параметров — сервер применит значения по умолчанию; страница возвращена.
    func test_fetchConversations_withoutParameters_requestsGetListWithoutQueryItems() async throws {
        let expected = ConversationsPage(conversations: [.singleStub], hasNext: false)
        networkService.stubbedResult = .success(expected)

        let page = try await sut.fetchConversations(offset: nil, count: nil)

        XCTAssertEqual(page, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/conversations/getList")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: запрос следующей страницы со сдвигом и размером страницы.
    /// Ожидание: оба параметра уходят в запрос строками.
    func test_fetchConversations_withParameters_passesThemToEndpoint() async throws {
        networkService.stubbedResult = .success(ConversationsPage(conversations: [], hasNext: false))

        _ = try await sut.fetchConversations(offset: 30, count: 30)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["offset": "30", "count": "30"])
    }

    /// Кейс: задан только размер страницы.
    /// Ожидание: незаданный `offset` в запрос не попадает.
    func test_fetchConversations_withCountOnly_omitsOffset() async throws {
        networkService.stubbedResult = .success(ConversationsPage(conversations: [], hasNext: false))

        _ = try await sut.fetchConversations(offset: nil, count: 10)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["count": "10"])
    }

    /// Кейс: сервер вернул бизнес-ошибку списка (невалидные параметры).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_fetchConversations_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.invalidParameters))

        do {
            _ = try await sut.fetchConversations(offset: -1, count: 0)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 1004))
        }
    }
}
