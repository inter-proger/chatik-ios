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
    /// Запросы списка по порядку — кроме сверки изменений.
    private(set) var requests: [(filter: ConversationListFilter, count: Int?)] = []
    /// Ответы на последовательные запросы сверки изменений (`changedAfter`); когда очередь пуста — ошибка. Отдельно
    /// от `stubbedPages`: сверка идёт в фоне после дельты и не должна забирать ответы других запросов.
    var stubbedChangePages: [Result<ConversationsPage, Error>] = []
    /// Запросы сверки изменений по порядку.
    private(set) var changeRequests: [(filter: ConversationListFilter, count: Int?)] = []
    /// Запросы `getBatch` по порядку.
    private(set) var batchRequests: [[Int]] = []
    /// Ответы на последовательные `markRead`; когда очередь пуста — ошибка.
    var stubbedReadInfos: [Result<ReadInfo, Error>] = []
    /// Запросы `markRead` по порядку.
    private(set) var markReadRequests: [(conversationId: Int, messageId: Int)] = []
    /// Ответы на последовательные `getMembersReadMeta`; когда очередь пуста — ошибка.
    var stubbedMembersReadMeta: [Result<[MemberReadMeta], Error>] = []
    /// Запросы `getMembersReadMeta` по порядку.
    private(set) var membersReadMetaRequests: [Int] = []
    /// Вызывается внутри `getMembersReadMeta` до возврата результата — пока запрос гарантированно выполняется.
    var onFetchMembersReadMeta: (@MainActor () async -> Void)?
    /// Вызывается внутри `markRead` до возврата результата — пока запрос гарантированно выполняется.
    var onMarkRead: (@MainActor () async -> Void)?
    /// Вызывается внутри любого запроса до возврата результата — пока вызывающий гарантированно ждёт ответа.
    var onRequest: (@MainActor () async -> Void)?

    func createSingle(userId: Int) async throws -> Conversation {
        createSingleUserIds.append(userId)
        await onRequest?()
        return try stubbedConversation.get()
    }

    func fetchConversations(filter: ConversationListFilter, count: Int?) async throws -> ConversationsPage {
        guard case .changedAfter = filter else {
            requests.append((filter, count))
            let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
            await onRequest?()
            return try result.get()
        }
        changeRequests.append((filter, count))
        let result = stubbedChangePages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedChangePages.removeFirst()
        await onRequest?()
        return try result.get()
    }

    func fetchConversations(ids: [Int]) async throws -> ConversationsBatch {
        batchRequests.append(ids)
        let result = stubbedBatches.isEmpty ? .failure(NetworkError.missingResponse) : stubbedBatches.removeFirst()
        await onRequest?()
        return try result.get()
    }

    func markRead(conversationId: Int, messageId: Int) async throws -> ReadInfo {
        markReadRequests.append((conversationId, messageId))
        let result = stubbedReadInfos.isEmpty ? .failure(NetworkError.missingResponse) : stubbedReadInfos.removeFirst()
        await onMarkRead?()
        return try result.get()
    }

    func fetchMembersReadMeta(conversationId: Int) async throws -> [MemberReadMeta] {
        membersReadMetaRequests.append(conversationId)
        let result = stubbedMembersReadMeta.isEmpty ? .failure(NetworkError.missingResponse) : stubbedMembersReadMeta.removeFirst()
        await onFetchMembersReadMeta?()
        return try result.get()
    }
}
