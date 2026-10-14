//
//  MessageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса сообщений: отдаёт заданные страницы, блоки и результат отправки, запоминает запросы.
/// `@unchecked Sendable`: тесты задают ответы до вызовов и читают запросы после них.
final class MessageServiceMock: MessageServiceProtocol, @unchecked Sendable {
    /// Ответы на последовательные запросы страниц; когда очередь пуста — ошибка.
    var stubbedPages: [Result<MessagesPage, Error>] = []
    /// Ответы на последовательные запросы блоков; когда очередь пуста — ошибка.
    var stubbedBatches: [Result<MessageBlocksBatch, Error>] = []
    var stubbedSentMessage: Result<Message, Error> = .failure(NetworkError.missingResponse)
    private(set) var pageRequests: [(conversationId: Int, filter: MessageListFilter)] = []
    private(set) var blockRequests: [[Int]] = []
    private(set) var sentRequests: [(conversationId: Int, text: String, clientId: String)] = []
    /// Вызывается внутри `fetchMessages` до возврата результата — пока идёт запрос страницы.
    var onFetch: (@MainActor () async -> Void)?
    /// Ответы на последовательные отправки; когда очередь пуста — `stubbedSentMessage`.
    var stubbedSentMessages: [Result<Message, Error>] = []
    /// Вызывается внутри `send` до возврата результата — пока запрос гарантированно выполняется.
    var onSend: (@MainActor () async -> Void)?

    func fetchMessages(conversationId: Int, filter: MessageListFilter) async throws -> MessagesPage {
        pageRequests.append((conversationId, filter))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onFetch?()
        return try result.get()
    }

    func fetchBlocks(ids: [Int]) async throws -> MessageBlocksBatch {
        blockRequests.append(ids)
        let result = stubbedBatches.isEmpty ? .failure(NetworkError.missingResponse) : stubbedBatches.removeFirst()
        return try result.get()
    }

    func send(conversationId: Int, text: String, clientId: String) async throws -> Message {
        sentRequests.append((conversationId, text, clientId))
        let result = stubbedSentMessages.isEmpty ? stubbedSentMessage : stubbedSentMessages.removeFirst()
        await onSend?()
        return try result.get()
    }

    func edit(messageId: Int, newText: String) async throws -> Message {
        throw NetworkError.missingResponse
    }
}
