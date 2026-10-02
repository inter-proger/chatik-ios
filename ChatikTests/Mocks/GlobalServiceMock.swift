//
//  GlobalServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок `/global/*`: отвечает из очередей результатов и считает вызовы.
/// `@unchecked Sendable`: вызывается только с main actor — из сервиса WebSocket и теста.
final class GlobalServiceMock: GlobalServiceProtocol, @unchecked Sendable {
    /// Ответы на последовательные `start()`; когда очередь пуста — `nil` (пользователь не авторизован).
    var startResults: [Result<WebsocketConnectInfo?, Error>] = []
    /// Ответы на последовательные `fetchWebsocketToken()`; когда очередь пуста — ошибка сети.
    var tokenResults: [Result<WebsocketConnectInfo, Error>] = []
    private(set) var startCallCount = 0
    private(set) var tokenCallCount = 0

    func start() async throws -> WebsocketConnectInfo? {
        startCallCount += 1
        guard !startResults.isEmpty else { return nil }
        return try startResults.removeFirst().get()
    }

    func fetchWebsocketToken() async throws -> WebsocketConnectInfo {
        tokenCallCount += 1
        guard !tokenResults.isEmpty else { throw NetworkError.transport(URLError(.notConnectedToInternet)) }
        return try tokenResults.removeFirst().get()
    }
}

extension WebsocketConnectInfo {
    /// Данные подключения с заданным токеном.
    /// - Parameter token: токен подключения.
    static func stub(token: String = "token") -> WebsocketConnectInfo {
        WebsocketConnectInfo(url: URL(string: "ws://localhost:8081/ws")!, token: token, expiresIn: 120)
    }
}
