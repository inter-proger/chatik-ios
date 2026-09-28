//
//  ConversationService.swift
//  Chatik
//

import Foundation

protocol ConversationServiceProtocol {
    /// Создаёт личную переписку с указанным пользователем либо возвращает уже существующую.
    func createSingle(userId: Int) async throws -> Conversation
    /// Возвращает страницу переписок текущего пользователя, сначала самые новые.
    /// Параметры передаются явно: значения по умолчанию в требовании протокола Swift не поддерживает,
    /// а объявленные только в реализации через протокол всё равно не работают.
    func fetchConversations(offset: Int?, count: Int?) async throws -> ConversationsPage
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

    /// Загружает страницу переписок через `GET /conversations/getList`.
    /// - Parameters:
    ///   - offset: сколько первых переписок пропустить; за следующей страницей увеличивается на количество
    ///     уже полученных. `nil` — с начала списка.
    ///   - count: размер страницы; `nil` — значение сервера по умолчанию (30), максимум 100.
    /// - Returns: страница переписок; запрашивать дальше имеет смысл, пока `hasNext` равен `true`.
    func fetchConversations(offset: Int?, count: Int?) async throws -> ConversationsPage {
        try await networkService.request(ConversationEndpoint.getList(offset: offset, count: count))
    }
}
