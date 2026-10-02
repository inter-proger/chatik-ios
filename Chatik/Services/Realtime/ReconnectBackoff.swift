//
//  ReconnectBackoff.swift
//  Chatik
//

import Foundation

/// Задержка переподключения к WebSocket: 1, 2, 4, 8, 16, 30 секунд (дальше 30) со случайным разбросом ±20%,
/// чтобы клиенты, потерявшие соединение одновременно (перезапуск сервера), не переподключались залпом.
struct ReconnectBackoff: Sendable {
    /// Базовые задержки по номеру попытки; последняя повторяется для всех следующих.
    static let baseDelays: [Duration] = [1, 2, 4, 8, 16, 30].map { .seconds($0) }
    /// Допустимый разброс задержки в обе стороны.
    static let jitter = 0.2

    /// Множитель задержки из диапазона `1 ± jitter`; подменяется в тестах.
    private let randomFactor: @Sendable () -> Double

    /// - Parameter randomFactor: множитель задержки из диапазона `1 ± jitter`.
    init(randomFactor: @escaping @Sendable () -> Double = { Double.random(in: (1 - jitter)...(1 + jitter)) }) {
        self.randomFactor = randomFactor
    }

    /// Задержка перед переподключением.
    /// - Parameter attempt: номер переподключения подряд, начиная с 0; сбрасывается после `auth` / `connected`.
    func delay(forAttempt attempt: Int) -> Duration {
        let base = Self.baseDelays[min(max(attempt, 0), Self.baseDelays.count - 1)]
        return base * randomFactor()
    }
}
