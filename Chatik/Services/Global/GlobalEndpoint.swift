//
//  GlobalEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/global/*`. Ответы приходят с `Cache-Control: no-store` (в них токен) и не кэшируются.
enum GlobalEndpoint: Endpoint {
    /// GET /global/start — данные для начала работы приложения; доступен без авторизации. Ответ: `GlobalStartResponse`.
    case start
    /// GET /global/getWebsocketToken — новый токен для переподключения к WebSocket; требует сессии.
    /// Ответ: `WebsocketTokenResponse`.
    case getWebsocketToken

    var path: String {
        switch self {
        case .start: return "/global/start"
        case .getWebsocketToken: return "/global/getWebsocketToken"
        }
    }

    var method: HTTPMethod { .get }
    var parameters: [String: String] { [:] }
    var headers: [String: String]? { nil }
}
