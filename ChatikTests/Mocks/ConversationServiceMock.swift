//
//  ConversationServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса переписок: возвращает заданные результаты и запоминает запросы.
final class ConversationServiceMock: ConversationServiceProtocol {
    var stubbedConversation: Result<Conversation, Error> = .failure(NetworkError.missingResponse)
    /// Ответы на последовательные запросы списка; когда очередь пуста — ошибка.
    var stubbedPages: [Result<ConversationsPage, Error>] = []
    /// Ответы на последовательные запросы `getBatch`; когда очередь пуста — ошибка.
    var stubbedBatches: [Result<ConversationsBatch, Error>] = []
    private(set) var createSingleUserIds: [Int] = []
    /// Запросы списка по порядку.
    private(set) var requests: [(filter: ConversationListFilter, count: Int?)] = []
    /// Запросы `getBatch` по порядку.
    private(set) var batchRequests: [[Int]] = []
    /// Вызывается внутри любого запроса до возврата результата — пока вызывающий гарантированно ждёт ответа.
    var onRequest: (@MainActor () async -> Void)?

    func createSingle(userId: Int) async throws -> Conversation {
        createSingleUserIds.append(userId)
        await onRequest?()
        return try stubbedConversation.get()
    }

    func fetchConversations(filter: ConversationListFilter, count: Int?) async throws -> ConversationsPage {
        requests.append((filter, count))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onRequest?()
        return try result.get()
    }

    func fetchConversations(ids: [Int]) async throws -> ConversationsBatch {
        batchRequests.append(ids)
        let result = stubbedBatches.isEmpty ? .failure(NetworkError.missingResponse) : stubbedBatches.removeFirst()
        await onRequest?()
        return try result.get()
    }
}
