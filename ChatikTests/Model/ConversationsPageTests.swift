//
//  ConversationsPageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationsPageTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: страница из документации с одной личной перепиской.
    /// Ожидание: переписка разобрана вместе с id собеседника, `hasNext` — из ответа.
    func test_decode_readsConversationsAndHasNext() throws {
        let json = """
        {
          "conversations": [
            {
              "conversationId": 1, "type": "single", "memberIds": [1, 2], "name": null, "avatar": null,
              "opponentUserId": 2
            }
          ],
          "hasNext": false
        }
        """

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.conversations.map(\.conversationId), [1])
        XCTAssertEqual(page.conversations.first?.opponentUserId, 2)
        XCTAssertFalse(page.hasNext)
    }

    /// Кейс: пустая страница со следующей страницей впереди.
    /// Ожидание: пустой список и `hasNext == true`.
    func test_decode_emptyPage_keepsHasNext() throws {
        let json = #"{"conversations":[],"hasNext":true}"#

        let page = try decoder.decode(ConversationsPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.conversations.isEmpty)
        XCTAssertTrue(page.hasNext)
    }

    // MARK: - Покрытый диапазон

    /// Кейс: набор страниц — первая/не первая, с продолжением и без, пустая, с нарушенным порядком.
    /// Ожидание: диапазон `conversationId`, который страница покрывает целиком, либо `nil`, если о нём ничего сказать нельзя.
    func test_coveredIdRange() {
        let cases: [(ids: [Int], hasNext: Bool, isFirstPage: Bool, expected: ClosedRange<Int>?)] = [
            ([5, 3], true, true, 3...Int.max),
            ([5, 3], false, true, Int.min...Int.max),
            ([5, 3], true, false, 3...5),
            ([5, 3], false, false, Int.min...5),
            ([], false, true, Int.min...Int.max),
            ([], true, true, nil),
            ([], false, false, nil),
            ([3, 5], true, false, nil),
            ([3, 5], true, true, nil),
            ([3, 5], false, true, nil),
            ([5, 9, 3], true, true, nil),
            ([9, 3, 5, 1], true, false, nil),
            ([5, 5, 3], true, false, nil),
            ([7], true, false, 7...7),
        ]

        for testCase in cases {
            let page = ConversationsPage(conversations: testCase.ids.map(makeConversation), hasNext: testCase.hasNext)

            XCTAssertEqual(page.coveredIdRange(isFirstPage: testCase.isFirstPage), testCase.expected, "\(testCase)")
        }
    }

    /// Групповая переписка с указанным идентификатором.
    /// - Parameter id: идентификатор переписки.
    private func makeConversation(id: Int) -> Conversation {
        Conversation(conversationId: id, type: .group, memberIds: [1], name: "Группа", avatar: nil, opponentUserId: nil)
    }
}
