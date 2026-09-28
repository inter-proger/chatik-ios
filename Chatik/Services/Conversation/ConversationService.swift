//
//  ConversationService.swift
//  Chatik
//

import Foundation

protocol ConversationServiceProtocol {
    /// Создаёт личную переписку с указанным пользователем либо возвращает уже существующую.
    func createSingle(userId: Int) async throws -> Conversation
}

final class ConversationService: ConversationServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Создаёт личную переписку через `POST /conversation/createSingle`.
    /// Повторный вызов для того же собеседника возвращает ту же переписку, а не ошибку.
    /// - Parameter userId: собеседник; не может совпадать с текущим пользователем (иначе код 5001).
    func createSingle(userId: Int) async throws -> Conversation {
        let response: ConversationResponse = try await networkService.request(ConversationEndpoint.createSingle(userId: userId))
        return response.conversation
    }
}
