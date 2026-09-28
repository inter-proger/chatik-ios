//
//  ConversationServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса переписок: возвращает заданный результат и запоминает собеседников.
final class ConversationServiceMock: ConversationServiceProtocol {
    var stubbedConversation: Result<Conversation, Error> = .failure(NetworkError.missingResponse)
    /// Ответы на последовательные запросы списка; когда очередь пуста — ошибка.
    var stubbedPages: [Result<ConversationsPage, Error>] = []
    private(set) var createSingleUserIds: [Int] = []
    private(set) var requests: [(offset: Int?, count: Int?)] = []
    /// Вызывается внутри `createSingle` до возврата результата — пока ViewModel гарантированно в состоянии создания.
    var onRequest: (@MainActor () async -> Void)?

    func createSingle(userId: Int) async throws -> Conversation {
        createSingleUserIds.append(userId)
        await onRequest?()
        return try stubbedConversation.get()
    }

    func fetchConversations(offset: Int?, count: Int?) async throws -> ConversationsPage {
        requests.append((offset, count))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onRequest?()
        return try result.get()
    }
}
