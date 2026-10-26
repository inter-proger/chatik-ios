//
//  ConversationStorageServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища списка переписок: отдаёт заданный кэш и запоминает записи.
final class ConversationStorageServiceMock: ConversationStorageServiceProtocol {
    /// Что возвращает `fetchList()`.
    var stubbedList: Result<(conversations: [Conversation], state: ConversationListState), Error> = .success(([], ConversationListState()))
    /// Вызывается внутри `fetchList` до возврата результата — пока идёт чтение кэша.
    var onFetchList: (@MainActor () async -> Void)?
    /// Записи `save(conversations:state:)` по порядку.
    private(set) var saves: [(conversations: [Conversation], state: ConversationListState?)] = []
    /// Записи `replaceList(with:state:)` по порядку.
    private(set) var replacements: [(conversations: [Conversation], state: ConversationListState)] = []

    /// Состояние из последней записи любого вида, которая его меняла.
    private(set) var lastState: ConversationListState?

    func fetchList() async throws -> (conversations: [Conversation], state: ConversationListState) {
        await onFetchList?()
        return try stubbedList.get()
    }

    func save(conversations: [Conversation], state: ConversationListState?) async throws {
        saves.append((conversations, state))
        lastState = state ?? lastState
    }

    func replaceList(with conversations: [Conversation], state: ConversationListState) async throws {
        replacements.append((conversations, state))
        lastState = state
    }

    /// Записи `delete(conversationId:state:)` по порядку.
    private(set) var deletions: [(conversationId: Int, state: ConversationListState)] = []
    /// Записи `save(state:)` по порядку.
    private(set) var stateSaves: [ConversationListState] = []

    func delete(conversationId: Int, state: ConversationListState) async throws {
        deletions.append((conversationId, state))
        lastState = state
    }

    func save(state: ConversationListState) async throws {
        stateSaves.append(state)
        lastState = state
    }

    func find(byId id: Int) async throws -> Conversation? {
        try stubbedList.get().conversations.first { $0.id == id }
    }
}
