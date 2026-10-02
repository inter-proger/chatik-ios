//
//  WebSocketConnection.swift
//  Chatik
//

import Foundation

/// Коды закрытия WebSocket-соединения, на которые клиент реагирует по-особому.
enum WebSocketCloseCode {
    /// Нормальное закрытие: не переподключаться.
    static let normal = 1000
    /// Обрыв без close-фрейма (сеть, таймаут) — выставляется клиентом, если сервер кода не прислал.
    static let abnormal = 1006
    /// Авторизация соединения не удалась; причина — в предшествующем `auth` / `connectionError`.
    static let authorizationFailed = 4001
    /// Сессия завершена (выход, повторный вход, удаление пользователя).
    static let sessionEnded = 4003
}

/// Ошибки одного WebSocket-соединения.
enum WebSocketConnectionError: Error, Equatable {
    /// Соединение закрыто с указанным кодом; дальше читать из него нечего.
    case closed(code: Int)
    /// Пришёл фрейм, который не разобрался как сообщение протокола; соединение продолжает работать.
    case malformedMessage
}

/// Одно WebSocket-соединение. `Sendable`: соединение закрывается из обработчика отмены задачи,
/// а пингуется из отдельной задачи.
protocol WebSocketConnectionProtocol: AnyObject, Sendable {
    /// Отправляет сообщение текстовым фреймом.
    func send(_ message: WebSocketClientMessage) async throws
    /// Ждёт следующее сообщение сервера.
    /// - Throws: `WebSocketConnectionError.closed`, когда соединение закрыто; `.malformedMessage` — фрейм не разобран.
    func receive() async throws -> WebSocketServerMessage
    /// Отправляет ping-фрейм и ждёт pong.
    func sendPing() async throws
    /// Закрывает соединение с указанным кодом; ожидающий `receive()` завершится ошибкой `.closed`.
    func close(code: Int)
}

/// Создаёт соединения: в приложении — поверх `URLSession`, в тестах — моки.
protocol WebSocketConnectionFactoryProtocol: Sendable {
    /// Открывает соединение по адресу из `WebsocketConnectInfo`.
    func makeConnection(url: URL) -> WebSocketConnectionProtocol
}

/// Фабрика соединений поверх отдельной `URLSession`: cookie сессии API не подставляются — соединение
/// открывается без дополнительных заголовков и авторизуется токеном.
final class URLSessionWebSocketConnectionFactory: WebSocketConnectionFactoryProtocol {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    /// Создаёт задачу WebSocket и сразу запускает handshake.
    /// - Parameter url: адрес WebSocket-сервера.
    func makeConnection(url: URL) -> WebSocketConnectionProtocol {
        URLSessionWebSocketConnection(task: session.webSocketTask(with: url))
    }
}

/// Соединение поверх `URLSessionWebSocketTask`. Сборка и разбор JSON идут вне main (`@concurrent`).
///
/// `@unchecked Sendable`: единственное состояние — задача `URLSession`, методы которой потокобезопасны.
final class URLSessionWebSocketConnection: WebSocketConnectionProtocol, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let decoder = JSONDecoder()

    /// - Parameter task: задача WebSocket; запускается здесь же.
    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    /// Кодирует сообщение в JSON и отправляет текстовым фреймом.
    /// - Parameter message: сообщение клиента.
    @concurrent
    func send(_ message: WebSocketClientMessage) async throws {
        let text = try message.encoded()
        do {
            try await task.send(.string(text))
        } catch {
            throw WebSocketConnectionError.closed(code: closeCode)
        }
    }

    /// Ждёт следующий фрейм и разбирает его. Бинарные фреймы протоколом не используются и считаются неразборчивыми.
    @concurrent
    func receive() async throws -> WebSocketServerMessage {
        let frame: URLSessionWebSocketTask.Message
        do {
            frame = try await task.receive()
        } catch {
            throw WebSocketConnectionError.closed(code: closeCode)
        }
        guard case let .string(text) = frame,
              let message = try? decoder.decode(WebSocketServerMessage.self, from: Data(text.utf8)) else {
            throw WebSocketConnectionError.malformedMessage
        }
        return message
    }

    /// Отправляет ping и ждёт pong; ошибка — соединение уже закрыто.
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                guard let error else { return continuation.resume() }
                continuation.resume(throwing: error)
            }
        }
    }

    /// Закрывает соединение. Клиент закрывает соединения только нормально, поэтому неизвестный код
    /// заменяется на 1000.
    /// - Parameter code: код закрытия.
    func close(code: Int) {
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
    }

    /// Код закрытия, присланный сервером; если сервер close-фрейм не прислал — 1006 (обрыв).
    private var closeCode: Int {
        task.closeCode == .invalid ? WebSocketCloseCode.abnormal : task.closeCode.rawValue
    }
}
