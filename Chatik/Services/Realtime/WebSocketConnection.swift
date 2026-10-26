//
//  WebSocketConnection.swift
//  Chatik
//

import Foundation
import os

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

    /// Отправляет ping и ждёт pong; ошибка — соединение уже закрыто или задача отменена.
    @concurrent
    func sendPing() async throws {
        try await Self.awaitPong { [task] handler in task.sendPing(pongReceiveHandler: handler) }
    }

    /// Ожидание pong: продолжение забирает первый ответ обработчика ping или отмена задачи.
    private struct PongWaiting: Sendable {
        var continuation: CheckedContinuation<Void, Error>?
        var isCancelled = false
    }

    /// Ждёт первый ответ обработчика ping. `URLSessionWebSocketTask.sendPing` при обрыве соединения может вызвать
    /// обработчик повторно, а продолжение возобновляется ровно один раз — поэтому повторные вызовы игнорируются.
    /// При отмене задачи ожидание сразу завершается, не дожидаясь обработчика; если задача отменена до начала,
    /// ping не отправляется. Не `private` — для тестов.
    /// - Parameter sendPing: отправляет ping и передаёт ответ в обработчик: `nil` — pong пришёл, иначе — ошибка.
    /// - Throws: ошибку из первого ответа обработчика; `CancellationError`, если задача отменена раньше.
    static func awaitPong(_ sendPing: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        let waiting = OSAllocatedUnfairLock(initialState: PongWaiting())
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let isCancelled = waiting.withLock { waiting in
                    waiting.continuation = continuation
                    return waiting.isCancelled
                }
                guard !isCancelled else { return resumePong(waiting, with: CancellationError()) }
                sendPing { error in resumePong(waiting, with: error) }
            }
        } onCancel: {
            waiting.withLock { $0.isCancelled = true }
            resumePong(waiting, with: CancellationError())
        }
    }

    /// Возобновляет ожидание pong, если оно ещё не возобновлено; повторные вызовы ничего не делают.
    /// - Parameters:
    ///   - waiting: ожидание pong.
    ///   - error: `nil` — pong пришёл, иначе — ошибка, с которой завершается ожидание.
    private static func resumePong(_ waiting: OSAllocatedUnfairLock<PongWaiting>, with error: Error?) {
        let continuation = waiting.withLock { waiting in
            defer { waiting.continuation = nil }
            return waiting.continuation
        }
        guard let continuation else { return }
        guard let error else { return continuation.resume() }
        continuation.resume(throwing: error)
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
