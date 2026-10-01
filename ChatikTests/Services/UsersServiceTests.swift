//
//  UsersServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UsersServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: UsersService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = UsersService(networkService: networkService)
    }

    /// Кейс: запрос первой страницы без фильтра и без явных параметров пагинации.
    /// Ожидание: GET /users/getList без параметров — сервер применит значения по умолчанию; страница возвращена.
    func test_fetchUsers_withoutParameters_requestsGetListWithoutQueryItems() async throws {
        let expected = UsersPage(users: [.stub], nextMaxId: 1, hasNext: true)
        networkService.stubbedResult = .success(expected)

        let page = try await sut.fetchUsers(query: nil, maxId: nil, count: nil)

        XCTAssertEqual(page, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/users/getList")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: запрос следующей страницы с фильтром, `maxId` и размером страницы.
    /// Ожидание: все три параметра уходят в запрос, числа — строками.
    func test_fetchUsers_withAllParameters_passesThemToEndpoint() async throws {
        networkService.stubbedResult = .success(UsersPage(users: [], nextMaxId: nil, hasNext: false))

        _ = try await sut.fetchUsers(query: "ivan", maxId: 5, count: 30)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["query": "ivan", "maxId": "5", "count": "30"])
    }

    /// Кейс: задан только фильтр.
    /// Ожидание: незаданные `maxId` и `count` в запрос не попадают.
    func test_fetchUsers_withQueryOnly_omitsPaginationParameters() async throws {
        networkService.stubbedResult = .success(UsersPage(users: [], nextMaxId: nil, hasNext: false))

        _ = try await sut.fetchUsers(query: "ivan", maxId: nil, count: nil)

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["query": "ivan"])
    }

    /// Кейс: поле поиска очищено — фильтр пустой или состоит из пробелов.
    /// Ожидание: параметр `query` в запрос не уходит — это равносильно списку без фильтра.
    func test_fetchUsers_blankQuery_omitsQueryParameter() async throws {
        let blankQueries = [
            "",
            "   ",
            "\n",
        ]

        for query in blankQueries {
            networkService = NetworkServiceMock()
            networkService.stubbedResult = .success(UsersPage(users: [], nextMaxId: nil, hasNext: false))
            sut = UsersService(networkService: networkService)

            _ = try await sut.fetchUsers(query: query, maxId: nil, count: nil)

            XCTAssertEqual(networkService.requestedEndpoints.first?.parameters, [:], query.debugDescription)
        }
    }

    /// Кейс: сервер вернул бизнес-ошибку (невалидные параметры запроса).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_fetchUsers_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.invalidParameters))

        do {
            _ = try await sut.fetchUsers(query: nil, maxId: nil, count: 0)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 1004))
        }
    }

    /// Кейс: запрос пользователей по списку id.
    /// Ожидание: GET /users/getBatch, id через запятую в порядке запроса; пачка возвращена без изменений.
    func test_fetchUsersByIds_requestsGetBatchWithCommaSeparatedIds() async throws {
        let expected = UsersBatch(users: [.stub], notFoundIds: [999])
        networkService.stubbedResult = .success(expected)

        let batch = try await sut.fetchUsers(ids: [2, 1, 999])

        XCTAssertEqual(batch, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/users/getBatch")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["userIds": "2,1,999"])
    }

    /// Кейс: сервер отклонил список id (пустой или длиннее 100).
    /// Ожидание: ошибка 1004 пробрасывается наружу без изменений.
    func test_fetchUsersByIds_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.invalidParameters))

        do {
            _ = try await sut.fetchUsers(ids: [])
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 1004))
        }
    }

    /// Кейс: эндпоинты пользователей — постраничный список и пачка по id.
    /// Ожидание: actions из ответа выполняются для списка, но не для пачки — её вызывает сам кэш пользователей
    /// при выполнении action `users`.
    func test_dispatchesActions_disabledOnlyForGetBatch() {
        XCTAssertTrue(UsersEndpoint.getList(query: nil, maxId: nil, count: nil).dispatchesActions)
        XCTAssertFalse(UsersEndpoint.getBatch(userIds: [1]).dispatchesActions)
    }
}
