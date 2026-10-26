//
//  GroupInfoStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища составов групп: держит составы в памяти и применяет запись как настоящее хранилище.
final class GroupInfoStorageServiceMock: GroupInfoStorageServiceProtocol {
    /// Сохранённые составы по группе.
    var stored: [Int: GroupInfo] = [:]
    /// Задерживает чтение состава до `open()`.
    var fetchGate: Gate?
    private(set) var savedInfos: [GroupInfo] = []
    private(set) var deletedConversationIds: [Int] = []

    func fetchConversationIds() async throws -> Set<Int> {
        Set(stored.keys)
    }

    func fetch(conversationId: Int) async throws -> GroupInfo? {
        await fetchGate?.wait()
        return stored[conversationId]
    }

    func save(_ info: GroupInfo, createsMissing: Bool) async throws {
        savedInfos.append(info)
        guard stored[info.conversationId] != nil || createsMissing else { return }
        guard info.version > stored[info.conversationId]?.version ?? .min else { return }
        stored[info.conversationId] = info
    }

    func delete(conversationId: Int) async throws {
        deletedConversationIds.append(conversationId)
        stored[conversationId] = nil
    }
}
