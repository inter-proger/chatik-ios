//
//  ConversationStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища переписок: отдаёт заданные переписки и запоминает сохранённые.
final class ConversationStorageServiceMock: ConversationStorageServiceProtocol {
    /// Что возвращают `fetchAll()` и `fetchLatest(limit:)`.
    var stubbedConversations: Result<[Conversation], Error> = .success([])
    /// Ошибка, которой завершается любое сохранение; `nil` — сохранение успешно.
    var stubbedSaveError: Error?
    private(set) var savedPages: [(page: ConversationsPage, isFirstPage: Bool)] = []
    private(set) var savedConversations: [Conversation] = []
    /// Вызывается внутри `fetchLatest` до возврата результата — пока идёт чтение кэша.
    var onFetchLatest: (@MainActor () async -> Void)?
    /// Лимиты, с которыми вызывался `fetchLatest`.
    private(set) var fetchLatestLimits: [Int] = []

    func save(conversation: Conversation) async throws {
        try await save(conversations: [conversation])
    }

    func save(conversations: [Conversation]) async throws {
        if let stubbedSaveError { throw stubbedSaveError }
        savedConversations += conversations
    }

    func save(page: ConversationsPage, isFirstPage: Bool) async throws {
        if let stubbedSaveError { throw stubbedSaveError }
        savedPages.append((page, isFirstPage))
    }

    func fetchAll() async throws -> [Conversation] {
        try stubbedConversations.get()
    }

    func fetchLatest(limit: Int) async throws -> [Conversation] {
        fetchLatestLimits.append(limit)
        await onFetchLatest?()
        return Array(try stubbedConversations.get().prefix(limit))
    }

    func find(byId id: Int) async throws -> Conversation? {
        try stubbedConversations.get().first { $0.id == id }
    }

    func delete(byId id: Int) async throws {}
}
