//
//  GlobalService.swift
//  Chatik
//

import Foundation

/// `Sendable`: сервисом пользуется менеджер WebSocket из своих задач.
protocol GlobalServiceProtocol: Sendable {
    /// Данные для начала работы: подключение к WebSocket или `nil`, если пользователь не авторизован.
    func start() async throws -> WebsocketConnectInfo?
    /// Новый токен для переподключения к WebSocket.
    func fetchWebsocketToken() async throws -> WebsocketConnectInfo
}

final class GlobalService: GlobalServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Вызывает `GET /global/start` — при запуске, после входа, регистрации и выхода, при возврате из фона.
    /// - Returns: данные подключения к WebSocket; `nil` — пользователь не авторизован, подключаться не нужно.
    func start() async throws -> WebsocketConnectInfo? {
        let response: GlobalStartResponse = try await networkService.request(GlobalEndpoint.start)
        return response.websocketConnectInfo
    }

    /// Вызывает `GET /global/getWebsocketToken` — перед каждым переподключением.
    /// - Returns: данные подключения с новым токеном.
    /// - Throws: `NetworkError.api(2003)`, если сессии нет: сетевой слой к этому моменту уже завершил её локально.
    func fetchWebsocketToken() async throws -> WebsocketConnectInfo {
        let response: WebsocketTokenResponse = try await networkService.request(GlobalEndpoint.getWebsocketToken)
        return response.websocketConnectInfo
    }
}
