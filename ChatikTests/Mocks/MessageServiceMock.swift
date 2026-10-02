//
//  MessageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса сообщений: отдаёт заданные страницы и результат отправки, запоминает запросы.
final class MessageServiceMock: MessageServiceProtocol {
    /// Ответы на последовательные запросы страниц; когда очередь пуста — ошибка.
    var stubbedPages: [Result<MessagesPage, Error>] = []
    var stubbedSentMessage: Result<Message, Error> = .failure(NetworkError.missingResponse)
    private(set) var pageRequests: [(conversationId: Int, blockId: Int?)] = []
    private(set) var sentRequests: [(conversationId: Int, text: String)] = []
    /// Вызывается внутри `fetchMessages` до возврата результата — пока идёт запрос страницы.
    var onFetch: (@MainActor () async -> Void)?
    /// Вызывается внутри `send` до возврата результата — пока ViewModel гарантированно в состоянии отправки.
    var onSend: (@MainActor () async -> Void)?

    func fetchMessages(conversationId: Int, blockId: Int?) async throws -> MessagesPage {
        pageRequests.append((conversationId, blockId))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onFetch?()
        return try result.get()
    }

    func fetchBlock(blockId: Int) async throws -> [Message] {
        []
    }

    func send(conversationId: Int, text: String) async throws -> Message {
        sentRequests.append((conversationId, text))
        await onSend?()
        return try stubbedSentMessage.get()
    }

    func edit(messageId: Int, newText: String) async throws -> Message {
        throw NetworkError.missingResponse
    }
}
