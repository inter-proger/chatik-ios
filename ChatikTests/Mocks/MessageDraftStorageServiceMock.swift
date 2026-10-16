//
//  MessageDraftStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища черновиков: держит черновики в памяти по пользователю, запоминает пачки изменений и умеет
/// отвечать ошибкой или задерживать чтение и запись.
final class MessageDraftStorageServiceMock: MessageDraftStorageServiceProtocol {
    /// Черновики по `userId`: `conversationId` → текст.
    var drafts: [Int: [Int: String]] = [:]
    /// Ошибка, которой завершается чтение; `nil` — чтение успешно.
    var stubbedFetchError: Error?
    /// Ошибка, которой завершается запись; `nil` — запись успешна.
    var stubbedApplyError: Error?
    /// Ошибка, которой завершается удаление просроченных; `nil` — удаление успешно.
    var stubbedDeleteError: Error?
    /// Вызывается внутри `fetchAll` до чтения — пока идёт загрузка.
    var onFetchAll: (@MainActor () async -> Void)?
    /// Задерживает только ближайшую запись: она ждёт `open()`, следующие проходят сразу.
    var nextApplyGate: Gate?
    /// Пачки `apply` по порядку, включая неудавшиеся.
    private(set) var applied: [(changes: [Int: MessageDraftChange], userId: Int)] = []
    private(set) var fetchCallCount = 0
    /// Границы `deleteAll(updatedBefore:)` по порядку вызовов.
    private(set) var deleteCutoffs: [Date] = []
    /// Сколько удалений просроченных было до каждого `fetchAll` — порядок удаления и чтения.
    private(set) var deleteCountsBeforeFetch: [Int] = []

    func fetchAll(userId: Int) async throws -> [Int: String] {
        fetchCallCount += 1
        deleteCountsBeforeFetch.append(deleteCutoffs.count)
        await onFetchAll?()
        if let stubbedFetchError { throw stubbedFetchError }
        return drafts[userId] ?? [:]
    }

    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws {
        applied.append((changes, userId))
        if let gate = nextApplyGate {
            nextApplyGate = nil
            await gate.wait()
        }
        if let stubbedApplyError { throw stubbedApplyError }
        for (conversationId, change) in changes {
            switch change {
            case let .save(text): drafts[userId, default: [:]][conversationId] = text
            case .delete: drafts[userId]?[conversationId] = nil
            }
        }
    }

    func deleteAll(updatedBefore date: Date) async throws {
        deleteCutoffs.append(date)
        if let stubbedDeleteError { throw stubbedDeleteError }
    }
}
