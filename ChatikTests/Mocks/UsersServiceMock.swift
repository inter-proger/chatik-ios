//
//  UsersServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса пользователей: отдаёт заданные страницы и пачки по очереди и запоминает параметры запросов.
/// Состояние изолировано на main actor: мок вызывают и из actor кэша пользователей, а тесты читают его синхронно.
/// Методы протокола `nonisolated` и переходят на main actor через `await`.
@MainActor
final class UsersServiceMock: UsersServiceProtocol {
    /// Ответы на последовательные запросы; когда очередь пуста — ошибка.
    var stubbedPages: [Result<UsersPage, Error>] = []
    private(set) var requests: [(query: String?, maxId: Int?, count: Int?)] = []
    /// Ответы на последовательные запросы пользователей по id; когда очередь пуста — ошибка.
    var stubbedBatches: [Result<UsersBatch, Error>] = []
    private(set) var batchRequests: [[Int]] = []
    /// Вызывается внутри `fetchUsers` до возврата результата — пока ViewModel гарантированно в состоянии загрузки.
    var onRequest: (@MainActor () async -> Void)?

    nonisolated func fetchUsers(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage {
        try await recordPageRequest(query: query, maxId: maxId, count: count)
    }

    nonisolated func fetchUsers(ids: [Int]) async throws -> UsersBatch {
        try await recordBatchRequest(ids: ids)
    }

    private func recordPageRequest(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage {
        requests.append((query, maxId, count))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onRequest?()
        return try result.get()
    }

    private func recordBatchRequest(ids: [Int]) async throws -> UsersBatch {
        batchRequests.append(ids)
        let result = stubbedBatches.isEmpty ? .failure(NetworkError.missingResponse) : stubbedBatches.removeFirst()
        await onRequest?()
        return try result.get()
    }
}
