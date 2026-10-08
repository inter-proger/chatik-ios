//
//  MessageSendQueueMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок очереди отправки: очередь задаёт тест, вызовы запоминаются, отправленные сообщения тест публикует через
/// `publishSent(_:)`.
@MainActor
final class MessageSendQueueMock: MessageSendQueueProtocol {
    var outgoingMessages: [OutgoingMessage] = []
    private(set) var startCallCount = 0
    private(set) var enqueued: [(text: String, conversationId: Int)] = []
    private(set) var retriedClientIds: [String] = []
    private(set) var deletedClientIds: [String] = []
    private(set) var confirmedBatches: [[Message]] = []
    private var continuations: [AsyncStream<Message>.Continuation] = []

    /// Число подписчиков на отправленные сообщения.
    var subscriberCount: Int {
        continuations.count
    }

    func start() {
        startCallCount += 1
    }

    func enqueue(text: String, conversationId: Int) {
        enqueued.append((text, conversationId))
    }

    func retry(clientId: String) {
        retriedClientIds.append(clientId)
    }

    func delete(clientId: String) {
        deletedClientIds.append(clientId)
    }

    func removeConfirmed(by messages: [Message]) {
        confirmedBatches.append(messages)
    }

    func sentMessages() -> AsyncStream<Message> {
        let (stream, continuation) = AsyncStream.makeStream(of: Message.self)
        continuations.append(continuation)
        return stream
    }

    /// Публикует сообщение, созданное сервером, всем подписчикам.
    /// - Parameter message: отправленное сообщение.
    func publishSent(_ message: Message) {
        continuations.forEach { $0.yield(message) }
    }
}
