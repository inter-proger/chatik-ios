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
