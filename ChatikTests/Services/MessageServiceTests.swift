//
//  MessageServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: MessageService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = MessageService(networkService: networkService)
    }

    /// Кейс: запрос самых новых сообщений переписки без `blockId`.
    /// Ожидание: GET /messages/getList только с `conversationId`; страница возвращена без изменений.
    func test_fetchMessages_withoutBlockId_requestsGetListWithConversationOnly() async throws {
        let expected = MessagesPage(messages: [.stub], nextBlockId: 1, hasNext: true)
        networkService.stubbedResult = .success(expected)

        let page = try await sut.fetchMessages(conversationId: 1, blockId: nil)

        XCTAssertEqual(page, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/messages/getList")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1"])
    }

    /// Кейс: запрос более старых сообщений с `nextBlockId` предыдущей страницы.
    /// Ожидание: `blockId` уходит в запрос вместе с `conversationId`.
    func test_fetchMessages_withBlockId_passesItToEndpoint() async throws {
        networkService.stubbedResult = .success(MessagesPage(messages: [], nextBlockId: nil, hasNext: false))

        _ = try await sut.fetchMessages(conversationId: 1, blockId: 3)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1", "blockId": "3"])
    }

    /// Кейс: запрос одного блока сообщений.
    /// Ожидание: GET /messages/getBlock с `blockId`, наружу отданы сообщения из поля `messages`.
    func test_fetchBlock_requestsEndpointAndUnwrapsMessages() async throws {
        networkService.stubbedResult = .success(MessagesBlock(messages: [.stub]))

        let messages = try await sut.fetchBlock(blockId: 2)

        XCTAssertEqual(messages, [.stub])
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/messages/getBlock")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["blockId": "2"])
    }

    /// Кейс: отправка текстового сообщения в переписку.
    /// Ожидание: POST /messages/send с `conversationId`, `text` и `clientId`, наружу отдано сообщение из поля `message`.
    func test_send_requestsEndpointAndUnwrapsMessage() async throws {
        networkService.stubbedResult = .success(MessageResponse(message: .stub))

        let message = try await sut.send(conversationId: 1, text: "Привет!", clientId: "abc-1")

        XCTAssertEqual(message, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/messages/send")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1", "text": "Привет!", "clientId": "abc-1"])
    }

    /// Кейс: редактирование своего сообщения.
    /// Ожидание: POST /messages/edit с `messageId` и `newText`, наружу отдано отредактированное сообщение.
    func test_edit_requestsEndpointAndUnwrapsMessage() async throws {
        networkService.stubbedResult = .success(MessageResponse(message: .editedStub))

        let message = try await sut.edit(messageId: 15, newText: "Привет всем!")

        XCTAssertEqual(message, .editedStub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/messages/edit")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["messageId": "15", "newText": "Привет всем!"])
    }

    /// Кейс: сервер вернул бизнес-ошибку списка (переписка не найдена).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_fetchMessages_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))

        do {
            _ = try await sut.fetchMessages(conversationId: 99, blockId: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 5002))
        }
    }

    /// Кейс: попытка отредактировать чужое сообщение.
    /// Ожидание: ошибка 6003 пробрасывается наружу без изменений.
    func test_edit_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.messageEditForbidden))

        do {
            _ = try await sut.edit(messageId: 16, newText: "Чужое")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 6003))
        }
    }
}
