//
//  MemberReadStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища прочтения другими участниками: держит указатели в памяти и применяет изменения как настоящее
/// хранилище, запоминает пачки и умеет задерживать чтение и запись.
final class MemberReadStorageServiceMock: MemberReadStorageServiceProtocol {
    /// Сохранённые указатели по `conversationId`.
    var stored: [Int: [Int: Int]] = [:]
    /// Ошибка, которой завершается запись; `nil` — запись успешна.
    var stubbedApplyError: Error?
    /// Ошибка, которой завершается чтение переписок с метой; `nil` — чтение успешно.
    var stubbedFetchConversationIdsError: Error?
    /// Сколько раз читались переписки с метой.
    private(set) var fetchConversationIdsCount = 0
    /// Задерживает чтение указателей до `open()`.
    var fetchPointersGate: Gate?
    /// Задерживает чтение переписок с метой до `open()`.
    var fetchConversationIdsGate: Gate?
    /// Задерживает только ближайшую запись: она ждёт `open()`, следующие проходят сразу.
    var nextApplyGate: Gate?
    /// Пачки `apply` по порядку, включая неудавшиеся.
    private(set) var applied: [[Int: MemberReadWrite]] = []

    func fetchConversationIds() async throws -> Set<Int> {
        if let gate = fetchConversationIdsGate {
            await gate.wait()
        }
        fetchConversationIdsCount += 1
        if let stubbedFetchConversationIdsError { throw stubbedFetchConversationIdsError }
        return Set(stored.keys)
    }

    func fetchPointers(conversationId: Int) async throws -> [Int: Int]? {
        if let gate = fetchPointersGate {
            await gate.wait()
        }
        return stored[conversationId]
    }

    func apply(_ writes: [Int: MemberReadWrite]) async throws {
        applied.append(writes)
        if let gate = nextApplyGate {
            nextApplyGate = nil
            await gate.wait()
        }
        if let stubbedApplyError { throw stubbedApplyError }
        for (conversationId, write) in writes {
            guard write.createsMissing || stored[conversationId] != nil else { continue }
            var pointers = (stored[conversationId] ?? [:]).filter { write.members?.contains($0.key) ?? true }
            pointers.merge(write.pointers, uniquingKeysWith: max)
            stored[conversationId] = pointers
        }
    }
}
