//
//  XCTestCase+YieldUntil.swift
//  ChatikTests
//

import XCTest

extension XCTestCase {
    /// Уступает main actor уже поставленным в очередь задачам, пока `condition` не выполнится.
    /// Нужен там, где состояние обновляется отдельной задачей (`Task { @MainActor in ... }`), порядок выполнения
    /// которой относительно теста не гарантирован. Ограничен по числу итераций: при регрессии тест упадёт,
    /// а не зависнет.
    /// - Parameters:
    ///   - attempts: максимальное число уступок.
    ///   - condition: условие, которого ждём.
    func yieldUntil(
        attempts: Int = 100,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<attempts where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Условие не выполнилось за \(attempts) итераций", file: file, line: line)
    }
}

extension XCTestCase {
    /// Ждёт, пока `condition` не выполнится, проверяя его на main actor каждые 5 мс. Нужен там, где состояние
    /// меняет работа вне главного потока (actor), — уступок main actor для неё недостаточно. Ограничен по времени:
    /// при регрессии тест упадёт, а не зависнет.
    /// - Parameters:
    ///   - timeout: сколько ждать, прежде чем считать условие невыполненным.
    ///   - condition: условие, которого ждём.
    @MainActor
    func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Условие не выполнилось за \(timeout)", file: file, line: line)
    }
}

extension XCTestCase {
    /// Уступает main actor заданное число раз — чтобы уже поставленные задачи успели выполниться там, где
    /// проверяется, что что-то **не** произошло.
    /// - Parameter count: число уступок.
    @nonobjc
    func yieldTimes(_ count: Int = 20) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }
}
