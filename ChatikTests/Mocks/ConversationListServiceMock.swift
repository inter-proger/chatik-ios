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
    var totalUnreadCount = 0
    /// Подтверждённое прочтение по `conversationId`; нет ключа — переписки нет в списке.
    var readStates: [Int: ConversationReadState] = [:]
    /// Непрочитанные для показа по `conversationId`; нет ключа — переписки нет в списке.
    var unreadCounts: [Int: Int] = [:]
    /// Запросы `markRead` по порядку.
    private(set) var markReadRequests: [(conversationId: Int, messageId: Int)] = []
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
    private(set) var sentReadInfos: [ReadInfo?] = []
    private(set) var editedMessages: [(message: Message, lastMessage: LastMessage?)] = []
    /// Метки удаления по `conversationId`.
    var removedVersions: [Int: Int] = [:]
    /// Переписки, для которых запрошена проверка членства, по порядку.
    private(set) var verifiedConversationIds: [Int] = []
    /// Вызовы `beginLeaving` / `endLeaving` по порядку: `"begin 12"`, `"end 12"`.
    private(set) var leavingCalls: [String] = []
    /// Применённые ответы `leave` по порядку.
    private(set) var appliedLeaves: [ConversationRemoval] = []
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

    func applySentMessage(_ message: Message, readInfo: ReadInfo?) {
        sentMessages.append(message)
        sentReadInfos.append(readInfo)
    }

    func readState(conversationId: Int) -> ConversationReadState? {
        readStates[conversationId]
    }

    func unreadCount(conversationId: Int) -> Int? {
        unreadCounts[conversationId]
    }

    func markRead(conversationId: Int, messageId: Int) {
        markReadRequests.append((conversationId, messageId))
    }

    func applyEditedMessage(_ message: Message, lastMessage: LastMessage?) {
        editedMessages.append((message, lastMessage))
    }
}

/// Группы: метки удаления, выход и проверка членства — состояние задаёт тест, вызовы запоминаются.
extension ConversationListServiceMock {
    func addRemovalObserver(_ observer: ConversationRemovalObserver) {}

    func conversation(id conversationId: Int) -> Conversation? {
        conversations.first { $0.conversationId == conversationId }
    }

    func isRemoved(conversationId: Int, changeVersion: Int) -> Bool {
        removedVersions[conversationId].map { changeVersion <= $0 } ?? false
    }

    func verifyMembership(conversationId: Int) {
        verifiedConversationIds.append(conversationId)
    }

    func beginLeaving(conversationId: Int) {
        leavingCalls.append("begin \(conversationId)")
    }

    func endLeaving(conversationId: Int) {
        leavingCalls.append("end \(conversationId)")
    }

    func applyLeave(_ removal: ConversationRemoval) {
        appliedLeaves.append(removal)
    }
}
