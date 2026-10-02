//
//  ReconnectBackoffTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ReconnectBackoffTests: XCTestCase {
    /// Кейс: попытки 0…7 без разброса.
    /// Ожидание: 1, 2, 4, 8, 16, 30, дальше 30 секунд.
    func test_delay_growsExponentiallyUpTo30Seconds() {
        let sut = ReconnectBackoff(randomFactor: { 1 })

        let delays = (0...7).map(sut.delay(forAttempt:))

        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30].map { .seconds($0) })
    }

    /// Кейс: множитель разброса на границах ±20%.
    /// Ожидание: задержка умножается на него.
    func test_delay_appliesJitter() {
        let low = ReconnectBackoff(randomFactor: { 0.8 })
        let high = ReconnectBackoff(randomFactor: { 1.2 })

        XCTAssertEqual(low.delay(forAttempt: 3) / .seconds(1), 6.4, accuracy: 0.001)
        XCTAssertEqual(high.delay(forAttempt: 5) / .seconds(1), 36, accuracy: 0.001)
    }

    /// Кейс: множитель по умолчанию, много попыток.
    /// Ожидание: каждая задержка в пределах ±20% от базовой.
    func test_defaultJitter_staysWithinBounds() {
        let sut = ReconnectBackoff()

        for _ in 0..<100 {
            let delay = sut.delay(forAttempt: 0)
            XCTAssertGreaterThanOrEqual(delay, .seconds(0.8))
            XCTAssertLessThanOrEqual(delay, .seconds(1.2))
        }
    }
}
