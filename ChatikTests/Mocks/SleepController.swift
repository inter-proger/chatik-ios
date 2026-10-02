//
//  SleepController.swift
//  ChatikTests
//

import Foundation

/// Управляемое ожидание: запоминает запрошенные паузы и завершает только разрешённые тестом; остальные длятся,
/// пока ждущую задачу не отменят. Так задержки переподключения и интервалы heartbeat не тратят время теста.
@MainActor
final class SleepController {
    /// Все запрошенные паузы по порядку.
    private(set) var requested: [Duration] = []
    private var allowances: [Duration: Int] = [:]

    /// Разрешает паузам указанной длительности завершиться сразу.
    /// - Parameters:
    ///   - duration: длительность паузы.
    ///   - times: сколько таких пауз завершить.
    func allow(_ duration: Duration, times: Int = 1) {
        allowances[duration, default: 0] += times
    }

    /// Пауза: разрешённая завершается сразу, иначе ждёт отмены.
    /// - Parameter duration: длительность паузы.
    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        if let allowance = allowances[duration], allowance > 0 {
            allowances[duration] = allowance - 1
            return
        }
        try await Task.sleep(for: .seconds(3600))
    }
}
