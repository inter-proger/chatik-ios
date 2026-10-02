//
//  RealtimeServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок соединения с WebSocket: считает запуски и остановки, события присылает тест через `send(_:)`.
@MainActor
final class RealtimeServiceMock: RealtimeServiceProtocol {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    /// Вызовы `start` и `stop` по порядку — чтобы проверять, что соединение закрыто до запроса, а открыто после.
    private(set) var calls: [String] = []
    private var continuations: [AsyncStream<RealtimeEvent>.Continuation] = []

    /// Число подписчиков на события.
    var subscriberCount: Int {
        continuations.count
    }

    func start() {
        startCallCount += 1
        calls.append("start")
    }

    func stop() async {
        stopCallCount += 1
        calls.append("stop")
    }

    func events() -> AsyncStream<RealtimeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeEvent.self)
        continuations.append(continuation)
        return stream
    }

    /// Доставляет событие всем подписчикам.
    /// - Parameter event: событие реального времени.
    func send(_ event: RealtimeEvent) {
        continuations.forEach { $0.yield(event) }
    }
}
