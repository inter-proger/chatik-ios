//
//  WebSocketConnectionTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class WebSocketConnectionTests: XCTestCase {
    /// Ответы, которые обработчик ping получает по очереди, и ожидаемый исход ожидания pong.
    private struct PongCase {
        let responses: [URLError?]
        let expectedError: URLError.Code?
    }

    /// Когда обработчик ping получает ответы.
    private enum Delivery: CaseIterable {
        /// Сразу, внутри отправки ping.
        case immediate
        /// Позже, из другой очереди, — как у `URLSessionWebSocketTask`.
        case later
    }

    /// Обработчик ping, переданный в отправку.
    private typealias PongHandler = @Sendable (Error?) -> Void

    /// Ждёт pong с переданной отправкой ping.
    /// - Parameter sendPing: отправка ping, получающая обработчик ответа.
    /// - Returns: код ошибки или `nil`, если pong пришёл.
    private func pongResult(_ sendPing: (@escaping PongHandler) -> Void) async -> URLError.Code? {
        do {
            try await URLSessionWebSocketConnection.awaitPong(sendPing)
            return nil
        } catch {
            return (error as? URLError)?.code
        }
    }

    /// Ждёт pong, передавая в обработчик ответы по очереди.
    /// - Parameters:
    ///   - responses: ответы обработчику: `nil` — pong, иначе — ошибка.
    ///   - delivery: когда обработчик получает ответы.
    /// - Returns: код ошибки или `nil`, если pong пришёл.
    private func awaitPong(responses: [URLError?], delivery: Delivery) async -> URLError.Code? {
        await pongResult { handler in
            let respond: @Sendable () -> Void = {
                for response in responses {
                    handler(response)
                }
            }
            switch delivery {
            case .immediate:
                respond()
            case .later:
                DispatchQueue.global().async(execute: respond)
            }
        }
    }

    /// Ждёт pong, передавая в обработчик ответы одновременно из глобальной очереди.
    /// - Parameter responses: ответы обработчику: `nil` — pong, иначе — ошибка.
    /// - Returns: код ошибки или `nil`, если pong пришёл.
    private func awaitPong(concurrentResponses responses: [URLError?]) async -> URLError.Code? {
        await pongResult { handler in
            DispatchQueue.global().async {
                DispatchQueue.concurrentPerform(iterations: responses.count) { index in
                    handler(responses[index])
                }
            }
        }
    }

    /// Кейс: обработчик ping вызван один раз или повторно (как при обрыве соединения) с разными ответами —
    /// сразу при отправке ping или позже из другой очереди.
    /// Ожидание: исход определяет первый ответ; повторные вызовы игнорируются и не роняют приложение.
    func test_awaitPong_resumesOnceWithFirstResponse() async {
        let cases = [
            PongCase(responses: [nil], expectedError: nil),
            PongCase(responses: [URLError(.networkConnectionLost)], expectedError: .networkConnectionLost),
            PongCase(responses: [URLError(.networkConnectionLost), URLError(.cancelled)], expectedError: .networkConnectionLost),
            PongCase(responses: [nil, URLError(.networkConnectionLost)], expectedError: nil),
            PongCase(responses: [URLError(.networkConnectionLost), nil], expectedError: .networkConnectionLost),
        ]

        for delivery in Delivery.allCases {
            for pongCase in cases {
                let result = await awaitPong(responses: pongCase.responses, delivery: delivery)
                XCTAssertEqual(result, pongCase.expectedError, "\(delivery): \(pongCase.responses)")
            }
        }
    }

    /// Кейс: обработчик ping вызван несколько раз одновременно из разных потоков с разными ошибками.
    /// Ожидание: ожидание pong завершается один раз, без падения, с одной из переданных ошибок.
    func test_awaitPong_concurrentResponses_resumesOnce() async {
        let responses: [URLError?] = [
            URLError(.networkConnectionLost),
            URLError(.cancelled),
            URLError(.timedOut),
            URLError(.notConnectedToInternet),
        ]
        let expectedErrors = Set(responses.compactMap { $0?.code })

        for _ in 0..<100 {
            let result = await awaitPong(concurrentResponses: responses)
            XCTAssertTrue(result.map(expectedErrors.contains) ?? false, "\(String(describing: result))")
        }
    }

    /// Кейс: задача, ждущая pong, отменена, пока обработчик ping не вызван; затем обработчик всё же вызван.
    /// Ожидание: ожидание сразу завершается `CancellationError`; поздний ответ игнорируется без падения.
    func test_awaitPong_cancelledWhileWaiting_throwsCancellationError() async {
        let (handlers, handlerSent) = AsyncStream<PongHandler>.makeStream()
        let waiting = Task {
            try await URLSessionWebSocketConnection.awaitPong { handler in handlerSent.yield(handler) }
        }
        var iterator = handlers.makeAsyncIterator()
        let handler = await iterator.next()

        waiting.cancel()
        let result = await waiting.result
        handler?(nil)

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
    }

    /// Кейс: задача отменена до начала ожидания pong.
    /// Ожидание: ping не отправляется, ожидание завершается `CancellationError`.
    func test_awaitPong_cancelledBeforeStart_skipsPing() async {
        let waiting = Task { () -> (Bool, Error?) in
            withUnsafeCurrentTask { $0?.cancel() }
            var isPingSent = false
            do {
                try await URLSessionWebSocketConnection.awaitPong { _ in isPingSent = true }
            } catch {
                return (isPingSent, error)
            }
            return (isPingSent, nil)
        }

        let (isPingSent, error) = await waiting.value

        XCTAssertFalse(isPingSent)
        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
    }
}
