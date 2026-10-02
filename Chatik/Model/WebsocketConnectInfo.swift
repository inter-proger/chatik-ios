//
//  WebsocketConnectInfo.swift
//  Chatik
//

import Foundation

/// Объект `WebsocketConnectInfo` из API — данные для одного подключения к WebSocket.
struct WebsocketConnectInfo: Decodable, Equatable, Sendable {
    /// Адрес WebSocket-сервера (`ws://` или `wss://`). Между вызовами не хранится — сервер может его сменить.
    let url: URL
    /// Одноразовый токен: гасится первой же попыткой авторизации соединения, даже неуспешной.
    let token: String
    /// Сколько секунд токен действителен с момента получения ответа (сейчас 120).
    let expiresIn: Int
}

/// Ответ `/global/start`: `websocketConnectInfo` равен `null`, если пользователь не авторизован.
/// Состав ответа будет расширяться — неизвестные поля пропускаются при разборе.
struct GlobalStartResponse: Decodable, Equatable {
    let websocketConnectInfo: WebsocketConnectInfo?
}

/// Ответ `/global/getWebsocketToken`.
struct WebsocketTokenResponse: Decodable, Equatable {
    let websocketConnectInfo: WebsocketConnectInfo
}
