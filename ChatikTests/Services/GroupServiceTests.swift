//
//  GroupServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class GroupServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: GroupService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = GroupService(networkService: networkService)
    }

    /// Кейс: исключение двух участников из группы 12.
    /// Ожидание: POST /groups/removeMembers с группой и id через запятую; ответ отдан как есть.
    func test_removeMembers_requestsEndpointAndReturnsResult() async throws {
        let expected = RemoveMembersResult(
            removedUserIds: [5],
            notRemovedUsersInfo: [UserErrorInfo(userId: 1, errorCode: 5008)],
            groupInfo: .make(conversationId: 12)
        )
        networkService.stubbedResult = .success(expected)

        let result = try await sut.removeMembers(conversationId: 12, userIds: [5, 1])

        XCTAssertEqual(result, expected)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/groups/removeMembers")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, ["conversationId": "12", "userIds": "5,1"])
    }
}
