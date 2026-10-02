//
//  WebSocketConnectionMock.swift
//  ChatikTests
//

import Foundation
import os
@testable import Chatik

/// Мок WebSocket-соединения: сообщения сервера и закрытие задаёт тест (`deliver`, `closeByServer`),
/// отправленное клиентом запоминается. Закрытие клиентом (`close`) завершает ожидающий `receive()` с этим кодом.
///
/// `@unchecked Sendable`: изменяемое состояние под замком, сообщения сервера идут через `AsyncStream`.
final class WebSocketConnectionMock: WebSocketConnectionProtocol, @unchecked Sendable {
    private enum Incoming {
        case message(WebSocketServerMessage)
        case closed(Int)
    }

    private struct State {
        var sent: [WebSocketClientMessage] = []
        var closeCodes: [Int] = []
        var closedCode: Int?
        var pingCount = 0
    }

    /// `true` — pong приходит сразу; `false` — ping ждёт, пока соединение не закроют.
    let answersPing: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let stream: AsyncStream<Incoming>
    private let continuation: AsyncStream<Incoming>.Continuation
    private var iterator: AsyncStream<Incoming>.Iterator

    /// - Parameter answersPing: отвечает ли соединение на ping.
    init(answersPing: Bool = true) {
        self.answersPing = answersPing
        (stream, continuation) = AsyncStream.makeStream(of: Incoming.self)
        iterator = stream.makeAsyncIterator()
    }

    /// Сообщения, отправленные клиентом, по порядку.
    var sent: [WebSocketClientMessage] { state.withLock { $0.sent } }
    /// Коды, с которыми клиент закрывал соединение.
    var closeCodes: [Int] { state.withLock { $0.closeCodes } }
    /// Сколько раз клиент отправлял ping.
    var pingCount: Int { state.withLock { $0.pingCount } }

    /// Присылает клиенту сообщение сервера.
    func deliver(_ message: WebSocketServerMessage) {
        continuation.yield(.message(message))
    }

    /// Присылает `auth` / `connected`.
    func deliverConnected() {
        deliver(WebSocketServerMessage(uid: UUID().uuidString, group: "auth", event: .connected, userIds: []))
    }

    /// Закрывает соединение со стороны сервера.
    /// - Parameter code: код закрытия.
    func closeByServer(code: Int) {
        continuation.yield(.closed(code))
    }

    func send(_ message: WebSocketClientMessage) async throws {
        if let code = state.withLock({ $0.closedCode }) { throw WebSocketConnectionError.closed(code: code) }
        state.withLock { $0.sent.append(message) }
    }

    func receive() async throws -> WebSocketServerMessage {
        if let code = state.withLock({ $0.closedCode }) { throw WebSocketConnectionError.closed(code: code) }
        switch await iterator.next() {
        case let .message(message):
            return message
        case let .closed(code):
            state.withLock { $0.closedCode = $0.closedCode ?? code }
            throw WebSocketConnectionError.closed(code: code)
        case nil:
            throw WebSocketConnectionError.closed(code: WebSocketCloseCode.abnormal)
        }
    }

    func sendPing() async throws {
        state.withLock { $0.pingCount += 1 }
        guard !answersPing else { return }
        while state.withLock({ $0.closedCode == nil && $0.closeCodes.isEmpty }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        throw WebSocketConnectionError.closed(code: WebSocketCloseCode.abnormal)
    }

    func close(code: Int) {
        state.withLock { $0.closeCodes.append(code) }
        continuation.yield(.closed(code))
    }
}

/// Мок фабрики соединений: отдаёт заранее заготовленные соединения по очереди, а когда они кончились —
/// новые без ответов сервера.
final class WebSocketConnectionFactoryMock: WebSocketConnectionFactoryProtocol, @unchecked Sendable {
    private struct State {
        var queued: [WebSocketConnectionMock] = []
        var made: [WebSocketConnectionMock] = []
        var urls: [URL] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameter connections: соединения, которые фабрика отдаст первыми.
    init(connections: [WebSocketConnectionMock] = []) {
        state.withLock { $0.queued = connections }
    }

    /// Открытые соединения по порядку.
    var made: [WebSocketConnectionMock] { state.withLock { $0.made } }
    /// Адреса, по которым открывались соединения.
    var urls: [URL] { state.withLock { $0.urls } }

    func makeConnection(url: URL) -> WebSocketConnectionProtocol {
        state.withLock { state in
            let connection = state.queued.isEmpty ? WebSocketConnectionMock() : state.queued.removeFirst()
            state.made.append(connection)
            state.urls.append(url)
            return connection
        }
    }
}
