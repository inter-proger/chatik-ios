//
//  OutgoingMessageStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища неотправленных сообщений: хранит записи в памяти по `clientId`.
final class OutgoingMessageStorageServiceMock: OutgoingMessageStorageServiceProtocol {
    /// Сохранённые сообщения по `clientId`.
    var messages: [String: OutgoingMessage] = [:]
    /// Ошибка, которой завершается любое сохранение; `nil` — сохранение успешно.
    var stubbedSaveError: Error?
    private(set) var deletedClientIds: [String] = []

    func save(message: OutgoingMessage) async throws {
        if let stubbedSaveError { throw stubbedSaveError }
        messages[message.clientId] = message
    }

    func fetchAll() async throws -> [OutgoingMessage] {
        messages.values.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(clientId: String) async throws {
        deletedClientIds.append(clientId)
        messages[clientId] = nil
    }
}
