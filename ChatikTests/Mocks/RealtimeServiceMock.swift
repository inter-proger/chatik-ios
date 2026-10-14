//
//  RealtimeServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок соединения с WebSocket: считает запуски и остановки.
@MainActor
final class RealtimeServiceMock: RealtimeServiceProtocol {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    /// Вызовы `start` и `stop` по порядку — чтобы проверять, что соединение закрыто до запроса, а открыто после.
    private(set) var calls: [String] = []
    /// Вызывается в `start()` — чтобы проверить, что к этому моменту уже сделано.
    var onStart: (() -> Void)?

    func start() {
        startCallCount += 1
        calls.append("start")
        onStart?()
    }

    func stop() async {
        stopCallCount += 1
        calls.append("stop")
    }
}
