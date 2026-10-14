//
//  MessageService.swift
//  Chatik
//

import Foundation

protocol MessageServiceProtocol: Sendable {
    /// Возвращает страницу сообщений переписки, сначала самые новые.
    func fetchMessages(conversationId: Int, filter: MessageListFilter) async throws -> MessagesPage
    /// Возвращает блоки сообщений целиком.
    func fetchBlocks(ids: [Int]) async throws -> MessageBlocksBatch
    /// Отправляет текстовое сообщение в переписку; повтор с тем же `clientId` не создаёт дубль.
    func send(conversationId: Int, text: String, clientId: String) async throws -> Message
    /// Заменяет текст своего сообщения.
    func edit(messageId: Int, newText: String) async throws -> Message
}

final class MessageService: MessageServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает сообщения переписки через `GET /messages/getList`.
    /// - Parameters:
    ///   - conversationId: переписка; чужая или несуществующая — ошибка 5002.
    ///   - filter: `.block` — обычная пагинация (за более старыми сообщениями передаётся `nextBlockId` предыдущей
    ///     страницы), `.receivedAfter` — дельта для синхронизации кэша.
    /// - Returns: страница из целых блоков; запрашивать дальше имеет смысл, пока `hasNext` равен `true`, — даже если
    ///   страница пуста.
    func fetchMessages(conversationId: Int, filter: MessageListFilter) async throws -> MessagesPage {
        try await networkService.request(MessageEndpoint.getList(conversationId: conversationId, filter: filter))
    }

    /// Загружает блоки целиком через `GET /messages/getBlockBatch`.
    /// - Parameter ids: 1–10 идентификаторов блоков, можно из разных переписок.
    /// - Returns: найденные блоки и id ненайденных (несуществующие и чужие неотличимы).
    func fetchBlocks(ids: [Int]) async throws -> MessageBlocksBatch {
        try await networkService.request(MessageEndpoint.getBlockBatch(blockIds: ids))
    }

    /// Отправляет сообщение через `POST /messages/send`.
    /// - Parameters:
    ///   - conversationId: переписка, в которую уходит сообщение.
    ///   - text: текст; после обрезки краевых пробелов и невидимых символов (см. `MessageTextValidator`) должен быть
    ///     длиной 1–4096 символов, иначе ошибка 1005.
    ///   - clientId: идентификатор, сгенерированный клиентом до отправки (UUID). Повтор запроса с тем же `clientId`
    ///     в этой переписке возвращает уже созданное сообщение; использованный в другой переписке — ошибка 6004.
    /// - Returns: созданное сообщение (или созданное раньше с тем же `clientId`).
    func send(conversationId: Int, text: String, clientId: String) async throws -> Message {
        let endpoint = MessageEndpoint.send(conversationId: conversationId, text: text, clientId: clientId)
        let response: MessageResponse = try await networkService.request(endpoint)
        return response.message
    }

    /// Редактирует сообщение через `POST /messages/edit`.
    /// - Parameters:
    ///   - messageId: сообщение текущего пользователя; чужое — ошибка 6003.
    ///   - newText: новый текст с теми же ограничениями, что и при отправке.
    /// - Returns: сообщение с `isEdited == true` и новым `updatedAt`. Если текст после обрезки совпал с текущим,
    ///   сервер сообщение не меняет и возвращает его как есть — `isEdited` и `updatedAt` прежние.
    func edit(messageId: Int, newText: String) async throws -> Message {
        let response: MessageResponse = try await networkService.request(MessageEndpoint.edit(messageId: messageId, newText: newText))
        return response.message
    }
}
