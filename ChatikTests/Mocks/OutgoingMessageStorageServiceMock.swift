//
//  OutgoingMessageStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища неотправленных сообщений: хранит записи в памяти по ключу `(senderId, clientId)`.
final class OutgoingMessageStorageServiceMock: OutgoingMessageStorageServiceProtocol {
    /// Сохранённые сообщения по ключу.
    private(set) var stored: [MessageClientKey: OutgoingMessage] = [:]
    /// Ошибка, которой завершается любое сохранение; `nil` — сохранение успешно.
    var stubbedSaveError: Error?
    /// Ошибка, которой завершается любое удаление одного сообщения; `nil` — удаление успешно.
    var stubbedDeleteError: Error?
    /// Ошибка, которой завершается чтение; `nil` — чтение успешно.
    var stubbedFetchError: Error?
    /// Вызывается в начале чтения — например, чтобы задержать его.
    var onFetch: (@MainActor () async -> Void)?
    private(set) var deletedClientIds: [String] = []
    /// Списки, переданные в `save(messages:)` (и в `save(message:)` — списком из одного), по порядку вызовов.
    private(set) var savedBatches: [[OutgoingMessage]] = []
    private(set) var fetchedSenderIds: [Int] = []
    /// Границы удаления просроченных сообщений, по порядку вызовов.
    private(set) var deletedBeforeDates: [Date] = []
    /// Порядок обращений к хранилищу: `deleteAll`, `fetchAll` — для проверки последовательности загрузки.
    private(set) var calls: [String] = []

    /// Сообщения пользователя с `senderId == 1` по `clientId` — для тестов с одним пользователем.
    var messages: [String: OutgoingMessage] {
        get { Dictionary(uniqueKeysWithValues: stored.values.filter { $0.senderId == 1 }.map { ($0.clientId, $0) }) }
        set {
            stored = stored.filter { $0.key.senderId != 1 }
            newValue.values.forEach { stored[$0.clientKey] = $0 }
        }
    }

    /// Кладёт сообщения в хранилище, не записывая вызовов.
    /// - Parameter messages: сообщения любых отправителей.
    func put(_ messages: [OutgoingMessage]) {
        messages.forEach { stored[$0.clientKey] = $0 }
    }

    func save(message: OutgoingMessage) async throws {
        try await save(messages: [message])
    }

    func save(messages: [OutgoingMessage]) async throws {
        if let stubbedSaveError { throw stubbedSaveError }
        savedBatches.append(messages)
        messages.forEach { stored[$0.clientKey] = $0 }
    }

    func fetchAll(senderId: Int) async throws -> [OutgoingMessage] {
        calls.append("fetchAll")
        fetchedSenderIds.append(senderId)
        await onFetch?()
        if let stubbedFetchError { throw stubbedFetchError }
        return stored.values.filter { $0.senderId == senderId }.sorted { $0.createdAt < $1.createdAt }
    }

    func delete(senderId: Int, clientId: String) async throws {
        if let stubbedDeleteError { throw stubbedDeleteError }
        deletedClientIds.append(clientId)
        stored[MessageClientKey(senderId: senderId, clientId: clientId)] = nil
    }

    func deleteAll(createdBefore date: Date) async throws {
        calls.append("deleteAll")
        deletedBeforeDates.append(date)
        stored = stored.filter { $0.value.createdAt >= date }
    }
}
