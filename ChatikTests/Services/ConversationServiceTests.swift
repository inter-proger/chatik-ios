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

    /// Кейс: запрос первой страницы списка без фильтра и без размера.
    /// Ожидание: GET /conversations/getList без параметров — сервер применит значения по умолчанию; страница возвращена.
    func test_fetchConversations_withoutParameters_requestsGetListWithoutQueryItems() async throws {
        let expected = ConversationsPage(conversations: [.singleStub], hasNext: false, totalUnreadCount: 2, changeVersion: 5)
        networkService.stubbedResult = .success(expected)

        let page = try await sut.fetchConversations(filter: .none(offset: nil), count: nil)

        XCTAssertEqual(page, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/conversations/getList")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: три вида фильтра списка вместе с размером страницы.
    /// Ожидание: параметры каждого фильтра уходят строками, незаданные (сдвиг, курсор) не попадают в запрос.
    func test_fetchConversations_filters_passParameters() async throws {
        let cases: [(filter: ConversationListFilter, parameters: [String: String])] = [
            (.none(offset: 30), ["offset": "30", "count": "30"]),
            (.positionUpdatedAfter(ServerTime(milliseconds: 1_790_846_400_123), offset: nil), ["positionUpdatedAfter": "1790846400123", "count": "30"]),
            (.positionUpdatedAfter(ServerTime(milliseconds: 5), offset: 30), ["positionUpdatedAfter": "5", "offset": "30", "count": "30"]),
            (.changedAfter(0), ["changedAfter": "0", "count": "30"]),
            (.changedAfter(118), ["changedAfter": "118", "count": "30"]),
        ]
        networkService.stubbedResult = .success(ConversationsPage(conversations: [], hasNext: false, totalUnreadCount: 0, changeVersion: 0))

        for testCase in cases {
            _ = try await sut.fetchConversations(filter: testCase.filter, count: 30)
        }

        XCTAssertEqual(networkService.requestedEndpoints.map(\.parameters), cases.map(\.parameters))
    }

    /// Кейс: отметка прочтения переписки до сообщения.
    /// Ожидание: POST /conversations/markRead с `conversationId` и `messageId`; наружу — `readInfo` из ответа.
    func test_markRead_postsAndUnwrapsReadInfo() async throws {
        let expected = ReadInfo.make(conversationId: 1, lastRead: 15, unread: 0, total: 3, version: 118)
        networkService.stubbedResult = .success(ReadInfoResponse(readInfo: expected))

        let readInfo = try await sut.markRead(conversationId: 1, messageId: 15)

        XCTAssertEqual(readInfo, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/conversations/markRead")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "1", "messageId": "15"])
    }

    /// Кейс: метка фильтра после вычета запаса синхронизации стала отрицательной.
    /// Ожидание: в запрос уходит 0 — отрицательное значение сервер отклонил бы ошибкой 1004.
    func test_fetchConversations_negativeTime_isClampedToZero() async throws {
        networkService.stubbedResult = .success(ConversationsPage(conversations: [], hasNext: false, totalUnreadCount: 0, changeVersion: 0))

        _ = try await sut.fetchConversations(filter: .positionUpdatedAfter(ServerTime(milliseconds: -5000), offset: nil), count: nil)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["positionUpdatedAfter": "0"])
    }

    /// Кейс: сервер вернул бизнес-ошибку списка (невалидные параметры).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_fetchConversations_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.invalidParameters))

        do {
            _ = try await sut.fetchConversations(filter: .none(offset: -1), count: 0)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 1004))
        }
    }

    /// Кейс: запрос переписок по id с повтором.
    /// Ожидание: GET /conversations/getBatch, id через запятую без повторов; ответ отдан наружу.
    func test_fetchConversationsByIds_requestsGetBatch() async throws {
        let expected = ConversationsBatch(conversations: [.singleStub], notFoundIds: [9])
        networkService.stubbedResult = .success(expected)

        let batch = try await sut.fetchConversations(ids: [1, 9, 1])

        XCTAssertEqual(batch, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/conversations/getBatch")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["conversationIds": "1,9"])
    }

    /// Кейс: id больше, чем сервер принимает за раз (150 при пределе 100).
    /// Ожидание: два запроса — на 100 и 50 id; ответы склеены.
    func test_fetchConversationsByIds_splitsIntoChunks() async throws {
        networkService.stubbedResult = .success(ConversationsBatch(conversations: [.singleStub], notFoundIds: [9]))

        let batch = try await sut.fetchConversations(ids: Array(1...150))

        let counts = networkService.requestedEndpoints.map { $0.parameters["conversationIds"]?.split(separator: ",").count }
        XCTAssertEqual(counts, [100, 50])
        XCTAssertEqual(batch, ConversationsBatch(conversations: [.singleStub, .singleStub], notFoundIds: [9, 9]))
    }
}
