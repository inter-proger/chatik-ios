//
//  BackgroundTaskRunnerMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок фоновых задач системы: сразу запускает работу и считает, сколько задач запрошено и сколько ещё идёт.
@MainActor
final class BackgroundTaskRunnerMock: BackgroundTaskRunning {
    /// Имена запрошенных задач по порядку; запрос фиксируется синхронно, до запуска работы.
    private(set) var requestedNames: [String] = []
    /// Сколько работ запущено и ещё не закончилось.
    private(set) var runningCount = 0

    @discardableResult
    func run(named name: String, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        requestedNames.append(name)
        runningCount += 1
        return Task {
            await work()
            runningCount -= 1
        }
    }
}
