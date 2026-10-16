//
//  BackgroundTaskRunner.swift
//  Chatik
//

import UIKit

@MainActor
protocol BackgroundTaskRunning {
    /// Синхронно просит систему не приостанавливать приложение и запускает работу. Фоновая задача завершается
    /// вместе с работой или по истечении отведённого системой времени; работа при этом не отменяется.
    /// - Parameters:
    ///   - name: имя фоновой задачи для отладки.
    ///   - work: работа, которую нужно успеть выполнить.
    /// - Returns: задача с работой — по ней можно дождаться её окончания.
    @discardableResult
    func run(named name: String, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never>
}

/// Фоновые задачи поверх `UIApplication.beginBackgroundTask`.
@MainActor
final class BackgroundTaskRunner: BackgroundTaskRunning {
    /// Запрашивает фоновую задачу до запуска работы: запрос из уже запущенной `Task` может опоздать — система
    /// успеет приостановить приложение.
    /// - Parameters:
    ///   - name: имя фоновой задачи для отладки.
    ///   - work: работа, которую нужно успеть выполнить.
    @discardableResult
    func run(named name: String, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let backgroundTask = BackgroundTask(named: name)
        return Task {
            await work()
            backgroundTask.end()
        }
    }
}

/// Одна фоновая задача системы. Завершается один раз: по окончании работы или по истечении времени — иначе
/// система завершит приложение за просроченную задачу.
@MainActor
private final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    /// Сразу запрашивает фоновую задачу.
    /// - Parameter name: имя для отладки.
    init(named name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    /// Завершает фоновую задачу; повторный вызов ничего не делает.
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
