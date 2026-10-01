//
//  MessageService.swift
//  Chatik
//

import Foundation

protocol MessageServiceProtocol {
    /// Возвращает страницу сообщений переписки, сначала самые новые.
    func fetchMessages(conversationId: Int, blockId: Int?) async throws -> MessagesPage
    /// Возвращает сообщения одного блока.
    func fetchBlock(blockId: Int) async throws -> [Message]
    /// Отправляет текстовое сообщение в переписку.
    func send(conversationId: Int, text: String) async throws -> Message
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
    ///   - blockId: блок, с которого начать (включительно); за более старыми сообщениями передаётся `nextBlockId`
    ///     предыдущей страницы. `nil` — с самого нового блока.
    /// - Returns: страница из целых блоков; запрашивать дальше имеет смысл, пока `hasNext` равен `true`.
    func fetchMessages(conversationId: Int, blockId: Int?) async throws -> MessagesPage {
        try await networkService.request(MessageEndpoint.getList(conversationId: conversationId, blockId: blockId))
    }

    /// Загружает один блок сообщений через `GET /messages/getBlock`.
    /// - Parameter blockId: блок; блок чужой переписки или несуществующий — ошибка 6002.
    /// - Returns: до 20 сообщений блока, сначала самые новые.
    func fetchBlock(blockId: Int) async throws -> [Message] {
        let block: MessagesBlock = try await networkService.request(MessageEndpoint.getBlock(blockId: blockId))
        return block.messages
    }

    /// Отправляет сообщение через `POST /messages/send`.
    /// - Parameters:
    ///   - conversationId: переписка, в которую уходит сообщение.
    ///   - text: текст; после обрезки пробелов должен быть длиной 1–4096 символов (иначе ошибка 1005).
    /// - Returns: созданное сообщение.
    func send(conversationId: Int, text: String) async throws -> Message {
        let response: MessageResponse = try await networkService.request(MessageEndpoint.send(conversationId: conversationId, text: text))
        return response.message
    }

    /// Редактирует сообщение через `POST /messages/edit`.
    /// - Parameters:
    ///   - messageId: сообщение текущего пользователя; чужое — ошибка 6003.
    ///   - newText: новый текст с теми же ограничениями, что и при отправке.
    /// - Returns: сообщение с `isEdited == true` и новым `updatedAt`.
    func edit(messageId: Int, newText: String) async throws -> Message {
        let response: MessageResponse = try await networkService.request(MessageEndpoint.edit(messageId: messageId, newText: newText))
        return response.message
    }
}
