//
//  NetworkPathMonitor.swift
//  Chatik
//

import Network
import os

/// Сообщает о появлении сети: WebSocket при этом переподключается сразу, не дожидаясь задержки.
final class NetworkPathMonitor: Sendable {
    private let monitor = NWPathMonitor()

    /// Сразу начинает следить за сетью.
    /// - Parameter onAvailable: вызывается на main, когда сеть появилась после отсутствия; на первое известное
    ///   состояние не вызывается.
    init(onAvailable: @escaping @MainActor @Sendable () -> Void) {
        let lastStatus = OSAllocatedUnfairLock<NWPath.Status?>(initialState: nil)
        monitor.pathUpdateHandler = { path in
            let previous = lastStatus.withLock { status in
                defer { status = path.status }
                return status
            }
            guard path.status == .satisfied, let previous, previous != .satisfied else { return }
            Task { @MainActor in onAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "Chatik.NetworkPathMonitor"))
    }

    deinit {
        monitor.cancel()
    }
}
