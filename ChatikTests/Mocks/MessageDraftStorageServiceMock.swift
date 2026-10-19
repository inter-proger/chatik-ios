//
//  MessageDraftStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища черновиков: держит черновики и правки в памяти по пользователю, применяет частичные изменения
/// как настоящее хранилище, запоминает пачки изменений и умеет отвечать ошибкой или задерживать чтение и запись.
final class MessageDraftStorageServiceMock: MessageDraftStorageServiceProtocol {
    /// Черновики по `userId`: `conversationId` → текст.
    var drafts: [Int: [Int: String]] = [:]
    /// Незавершённые правки по `userId`: `conversationId` → правка.
    var edits: [Int: [Int: MessageEditDraft]] = [:]
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

    func fetchAll(userId: Int) async throws -> [Int: MessageDraft] {
        fetchCallCount += 1
        deleteCountsBeforeFetch.append(deleteCutoffs.count)
        await onFetchAll?()
        if let stubbedFetchError { throw stubbedFetchError }
        let texts = drafts[userId] ?? [:]
        let userEdits = edits[userId] ?? [:]
        let ids = Set(texts.keys).union(userEdits.keys)
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, MessageDraft(text: texts[$0], edit: userEdits[$0])) })
    }

    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws {
        applied.append((changes, userId))
        if let gate = nextApplyGate {
            nextApplyGate = nil
            await gate.wait()
        }
        if let stubbedApplyError { throw stubbedApplyError }
        for (conversationId, change) in changes {
            if let text = change.text {
                drafts[userId, default: [:]][conversationId] = text
            }
            if let edit = change.edit {
                edits[userId, default: [:]][conversationId] = edit
            }
        }
    }

    func deleteAll(updatedBefore date: Date) async throws {
        deleteCutoffs.append(date)
        if let stubbedDeleteError { throw stubbedDeleteError }
    }
}
