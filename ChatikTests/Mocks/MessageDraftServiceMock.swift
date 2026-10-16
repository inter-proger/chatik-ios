//
//  MessageDraftServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса черновиков: черновики задаёт тест (наблюдаются через Observation), вызовы запоминаются.
@MainActor
@Observable
final class MessageDraftServiceMock: MessageDraftServiceProtocol {
    /// Вызов `update` или `save`.
    struct Call: Equatable {
        let text: String
        let conversationId: Int
        let userId: Int
    }

    /// Черновики по `conversationId`.
    var drafts: [Int: String] = [:]
    private(set) var updates: [Call] = []
    private(set) var saves: [Call] = []
    private(set) var removals: [(conversationId: Int, userId: Int)] = []
    private(set) var loadedUserIds: [Int] = []
    /// Вызывается внутри `load` — пока идёт загрузка.
    @ObservationIgnored var onLoad: (@MainActor () async -> Void)?

    func draft(for conversationId: Int) -> String? {
        drafts[conversationId]
    }

    func hasDraft(for conversationId: Int) -> Bool {
        drafts[conversationId] != nil
    }

    func update(text: String, conversationId: Int, userId: Int) {
        updates.append(Call(text: text, conversationId: conversationId, userId: userId))
    }

    func save(text: String, conversationId: Int, userId: Int) {
        saves.append(Call(text: text, conversationId: conversationId, userId: userId))
    }

    func remove(conversationId: Int, userId: Int) {
        removals.append((conversationId, userId))
    }

    func load(userId: Int) async {
        loadedUserIds.append(userId)
        await onLoad?()
    }
}
