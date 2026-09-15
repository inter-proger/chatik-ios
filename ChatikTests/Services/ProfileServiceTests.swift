//
//  ProfileServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ProfileServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: ProfileService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = ProfileService(networkService: networkService)
    }

    /// Кейс: запрос профиля.
    /// Ожидание: GET /profile/get без параметров, возвращён пользователь из ответа.
    func test_fetchProfile_requestsGetEndpointAndReturnsUser() async throws {
        let expected = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
        networkService.stubbedResult = .success(expected)

        let user = try await sut.fetchProfile()

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/profile/get")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: установка аватара.
    /// Ожидание: POST /profile/setAvatar с `file_id`, возвращён обновлённый пользователь.
    func test_setAvatar_requestsSetAvatarEndpointWithFileId() async throws {
        let expected = User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub)
        networkService.stubbedResult = .success(expected)

        let user = try await sut.setAvatar(fileId: 42)

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/profile/setAvatar")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["file_id": "42"])
    }

    /// Кейс: удаление аватара.
    /// Ожидание: POST /profile/removeAvatar без параметров, возвращён пользователь без аватара.
    func test_removeAvatar_requestsRemoveAvatarEndpoint() async throws {
        let expected = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
        networkService.stubbedResult = .success(expected)

        let user = try await sut.removeAvatar()

        XCTAssertEqual(user, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/profile/removeAvatar")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, [:])
    }

    /// Кейс: сервер вернул бизнес-ошибку (файл не является изображением).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_setAvatar_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.fileNotImage))

        do {
            _ = try await sut.setAvatar(fileId: 1)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 3003))
        }
    }
}
