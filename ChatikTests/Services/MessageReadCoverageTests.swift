//
//  MessageReadCoverageTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageReadCoverageTests: XCTestCase {
    /// Кейс: интервалы вперемешку — пересекающиеся, смежные, пустой и отдельный.
    /// Ожидание: пересекающиеся и смежные склеены, пустой отброшен, порядок по возрастанию.
    func test_init_mergesAndSorts() {
        let sut = MessageReadCoverage([
            .init(after: 20, upTo: 25),
            .init(after: 0, upTo: 10),
            .init(after: 5, upTo: 12),
            .init(after: 12, upTo: 14),
            .init(after: 30, upTo: 30),
        ])

        XCTAssertEqual(sut.ranges, [.init(after: 0, upTo: 14), .init(after: 20, upTo: 25)])
    }

    /// Кейс: покрытие `(0, 14]` и `(20, 25]`.
    /// Ожидание: границы полуинтервалов: `after` не входит, `upTo` входит; промежуток не прочитан.
    func test_contains_halfOpenBounds() {
        let sut = MessageReadCoverage([.init(after: 0, upTo: 14), .init(after: 20, upTo: 25)])
        let cases: [(messageId: Int, expected: Bool)] = [
            (1, true),
            (14, true),
            (15, false),
            (20, false),
            (21, true),
            (25, true),
            (26, false),
        ]

        for (messageId, expected) in cases {
            XCTAssertEqual(sut.contains(messageId), expected, "\(messageId)")
        }
    }
}
