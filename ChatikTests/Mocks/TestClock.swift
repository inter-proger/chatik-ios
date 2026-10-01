//
//  TestClock.swift
//  ChatikTests
//

import Foundation
import os

/// Подменяемое текущее время для тестов устаревания. Потокобезопасно: время читается из actor кэша
/// пользователей, а сдвигается тестом с main actor.
final class TestClock: Sendable {
    private let date: OSAllocatedUnfairLock<Date>

    /// - Parameter date: начальное время.
    init(_ date: Date) {
        self.date = OSAllocatedUnfairLock(initialState: date)
    }

    /// Текущее время часов.
    var now: Date {
        date.withLock { $0 }
    }

    /// Сдвигает часы вперёд.
    /// - Parameter interval: на сколько секунд.
    func advance(by interval: TimeInterval) {
        date.withLock { $0 += interval }
    }
}
