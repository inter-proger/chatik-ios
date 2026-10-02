//
//  MessageStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища сообщений: отдаёт заданные сообщения и запоминает сохранённые.
final class MessageStorageServiceMock: MessageStorageServiceProtocol {
    /// Что возвращает `fetchLatest`.
    var stubbedMessages: Result<[Message], Error> = .success([])
    /// Ошибка, которой завершается любое сохранение; `nil` — сохранение успешно.
    var stubbedSaveError: Error?
    private(set) var savedMessages: [Message] = []
    private(set) var fetchLatestRequests: [(conversationId: Int, limit: Int)] = []

    func save(message: Message) async throws {
        try await save(messages: [message])
    }

    func save(messages: [Message]) async throws {
        if let stubbedSaveError { throw stubbedSaveError }
        savedMessages += messages
    }

    func fetchLatest(conversationId: Int, limit: Int) async throws -> [Message] {
        fetchLatestRequests.append((conversationId, limit))
        return Array(try stubbedMessages.get().prefix(limit))
    }

    func find(byId id: Int) async throws -> Message? {
        try stubbedMessages.get().first { $0.id == id }
    }

    func delete(byId id: Int) async throws {}
}
