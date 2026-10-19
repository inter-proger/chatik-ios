//
//  ConversationListServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок списка переписок: состояние задаёт тест, вызовы запоминаются.
@MainActor
@Observable
final class ConversationListServiceMock: ConversationListServiceProtocol {
    var conversations: [Conversation] = []
    var isSyncing = false
    var isLoadingNextPage = false
    var hasMorePages = false
    var isLoaded = false
    /// Чем завершается `synchronizeIfNeeded()`; `nil` — успешно.
    var stubbedSynchronizeIfNeededError: Error?
    /// Чем завершается `refresh()`; `nil` — успешно.
    var stubbedRefreshError: Error?
    private(set) var startCallCount = 0
    private(set) var synchronizeCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var synchronizeIfNeededCallCount = 0
    private(set) var nextPageRequests: [Int] = []
    private(set) var applied: [Conversation] = []
    private(set) var sentMessages: [Message] = []
    private(set) var editedMessages: [(message: Message, lastMessage: LastMessage?)] = []
    /// Вызывается в `start()` — чтобы проверить, что к этому моменту уже сделано.
    var onStart: (() -> Void)?

    func start() {
        startCallCount += 1
        onStart?()
    }

    func synchronize() {
        synchronizeCallCount += 1
    }

    func synchronizeIfNeeded() async throws {
        synchronizeIfNeededCallCount += 1
        if let stubbedSynchronizeIfNeededError { throw stubbedSynchronizeIfNeededError }
    }

    func refresh() async throws {
        refreshCallCount += 1
        if let stubbedRefreshError { throw stubbedRefreshError }
    }

    func loadNextPageIfNeeded(currentConversationId: Int) {
        nextPageRequests.append(currentConversationId)
    }

    func apply(_ conversation: Conversation) {
        applied.append(conversation)
    }

    func applySentMessage(_ message: Message) {
        sentMessages.append(message)
    }

    func applyEditedMessage(_ message: Message, lastMessage: LastMessage?) {
        editedMessages.append((message, lastMessage))
    }
}
