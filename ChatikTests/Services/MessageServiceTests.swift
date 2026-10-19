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

        let page = try await sut.fetchMessages(conversationId: 1, filter: .block(nil))

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

        _ = try await sut.fetchMessages(conversationId: 1, filter: .block(3))

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1", "blockId": "3"])
    }

    /// Кейс: запрос дельты для синхронизации кэша с меткой `receivedAfter`.
    /// Ожидание: метка уходит в миллисекундах вместо `blockId`.
    func test_fetchMessages_receivedAfter_passesMarkWithoutBlockId() async throws {
        networkService.stubbedResult = .success(MessagesPage(messages: [], nextBlockId: nil, hasNext: false, updatedBlockIds: []))

        _ = try await sut.fetchMessages(conversationId: 1, filter: .receivedAfter(ServerTime(milliseconds: 1_790_850_000_456)))

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1", "receivedAfter": "1790850000456"])
    }

    /// Кейс: метка с запасом у начала эпохи отрицательна.
    /// Ожидание: уходит 0 — сервер не принимает отрицательную метку (ошибка 1004).
    func test_fetchMessages_negativeReceivedAfter_isClampedToZero() async throws {
        networkService.stubbedResult = .success(MessagesPage(messages: [], nextBlockId: nil, hasNext: false))

        _ = try await sut.fetchMessages(conversationId: 1, filter: .receivedAfter(ServerTime(milliseconds: -4000)))

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters["receivedAfter"], "0")
    }

    /// Кейс: запрос нескольких блоков целиком.
    /// Ожидание: GET /messages/getBlockBatch с id через запятую; ответ возвращён без изменений.
    func test_fetchBlocks_requestsBatchWithCommaSeparatedIds() async throws {
        let block = MessageBlock(blockId: 2, conversationId: 1, messages: [.stub], updatedAt: nil)
        let expected = MessageBlocksBatch(blocks: [block], notFoundIds: [9])
        networkService.stubbedResult = .success(expected)

        let batch = try await sut.fetchBlocks(ids: [2, 9])

        XCTAssertEqual(batch, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/messages/getBlockBatch")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["blockIds": "2,9"])
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
    /// Ожидание: POST /messages/edit с `messageId` и `newText`, наружу отдан ответ целиком.
    func test_edit_requestsEndpointAndReturnsResult() async throws {
        let expected = MessageEditResult(message: .editedStub, lastMessage: LastMessage(message: .editedStub))
        networkService.stubbedResult = .success(expected)

        let result = try await sut.edit(messageId: 15, newText: "Привет всем!")

        XCTAssertEqual(result, expected)
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
            _ = try await sut.fetchMessages(conversationId: 99, filter: .block(nil))
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
