//
//  UsersServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса пользователей: отдаёт заданные страницы по очереди и запоминает параметры запросов.
final class UsersServiceMock: UsersServiceProtocol {
    /// Ответы на последовательные запросы; когда очередь пуста — ошибка.
    var stubbedPages: [Result<UsersPage, Error>] = []
    private(set) var requests: [(query: String?, maxId: Int?, count: Int?)] = []
    /// Вызывается внутри `fetchUsers` до возврата результата — пока ViewModel гарантированно в состоянии загрузки.
    var onRequest: (@MainActor () async -> Void)?

    func fetchUsers(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage {
        requests.append((query, maxId, count))
        let result = stubbedPages.isEmpty ? .failure(NetworkError.missingResponse) : stubbedPages.removeFirst()
        await onRequest?()
        return try result.get()
    }
}
