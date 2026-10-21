//
//  ConversationService.swift
//  Chatik
//

import Foundation

protocol ConversationServiceProtocol {
    /// Создаёт личную переписку с указанным пользователем либо возвращает уже существующую.
    func createSingle(userId: Int) async throws -> Conversation
    /// Возвращает страницу переписок текущего пользователя с учётом фильтра.
    /// Параметры передаются явно: значения по умолчанию в требовании протокола Swift не поддерживает,
    /// а объявленные только в реализации через протокол всё равно не работают.
    func fetchConversations(filter: ConversationListFilter, count: Int?) async throws -> ConversationsPage
    /// Возвращает переписки по списку id.
    func fetchConversations(ids: [Int]) async throws -> ConversationsBatch
    /// Отмечает прочитанными сообщения переписки до `messageId` включительно.
    func markRead(conversationId: Int, messageId: Int) async throws -> ReadInfo
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
    ///   - filter: фильтр и сдвиг (или курсор) страницы.
    ///   - count: размер страницы; `nil` — значение сервера по умолчанию (30), максимум 100.
    /// - Returns: страница переписок; запрашивать дальше имеет смысл, пока `hasNext` равен `true`.
    func fetchConversations(filter: ConversationListFilter, count: Int?) async throws -> ConversationsPage {
        try await networkService.request(ConversationEndpoint.getList(filter: filter, count: count))
    }

    /// Загружает переписки по id через `GET /conversations/getBatch`. Больше `ConversationEndpoint.maxBatchCount`
    /// id за раз сервер не принимает — лишние запрашиваются следующими запросами, ответы склеиваются.
    /// - Parameter ids: идентификаторы переписок; повторы игнорируются.
    /// - Returns: найденные переписки в порядке запроса и id ненайденных.
    func fetchConversations(ids: [Int]) async throws -> ConversationsBatch {
        var seenIds = Set<Int>()
        let uniqueIds = ids.filter { seenIds.insert($0).inserted }
        var conversations: [Conversation] = []
        var notFoundIds: [Int] = []
        for start in stride(from: 0, to: uniqueIds.count, by: ConversationEndpoint.maxBatchCount) {
            let chunk = Array(uniqueIds[start..<min(start + ConversationEndpoint.maxBatchCount, uniqueIds.count)])
            let batch: ConversationsBatch = try await networkService.request(ConversationEndpoint.getBatch(ids: chunk))
            conversations += batch.conversations
            notFoundIds += batch.notFoundIds
        }
        return ConversationsBatch(conversations: conversations, notFoundIds: notFoundIds)
    }

    /// Отмечает прочтение через `POST /conversations/markRead`. Идемпотентен: повтор или более старый `messageId`
    /// возвращает текущее прочтение без изменений и без события.
    /// - Parameters:
    ///   - conversationId: переписка; чужая или несуществующая — ошибка 5002.
    ///   - messageId: последнее прочитанное сообщение этой переписки; из другой переписки — ошибка 6001.
    /// - Returns: прочтение переписки и общий счётчик на версии ответа.
    func markRead(conversationId: Int, messageId: Int) async throws -> ReadInfo {
        let response: ReadInfoResponse = try await networkService.request(
            ConversationEndpoint.markRead(conversationId: conversationId, messageId: messageId)
        )
        return response.readInfo
    }
}
