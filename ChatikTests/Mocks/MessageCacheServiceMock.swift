//
//  MessageCacheServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок кэша сообщений для очереди отправки и сервиса правок: запоминает отправленные и отредактированные
/// сообщения; остальное — заглушки.
@MainActor
final class MessageCacheServiceMock: MessageCacheServiceProtocol {
    /// Сообщения, переданные в `applySent`, по порядку.
    private(set) var sentMessages: [Message] = []
    /// Вызывается внутри `applySent` до записи — пока запись гарантированно выполняется.
    var onApplySent: (@MainActor () async -> Void)?
    /// Что возвращает `applySent`: не `.written` — сообщение в `sentMessages` не попадает.
    var stubbedApplySentResult = SentMessageWriteResult.written
    /// Сообщения, переданные в `applyEdited`, по порядку.
    private(set) var editedMessages: [Message] = []
    /// Вызывается внутри `applyEdited` после того, как сообщение запомнено, — пока запись идёт.
    var onApplyEdited: (@MainActor () async -> Void)?

    @MainActor
    func isSynced(conversationId: Int) async -> Bool {
        false
    }

    @MainActor
    func cacheState(conversationId: Int) async throws -> MessageCacheState? {
        nil
    }

    @MainActor
    func changes(conversationId: Int) async -> AsyncStream<MessageCacheChange> {
        AsyncStream { $0.finish() }
    }

    @MainActor
    func beginSync(conversationId: Int) async -> MessageSyncToken {
        MessageSyncToken(id: 1, conversationId: conversationId, connection: nil)
    }

    @MainActor
    func applySync(_ result: MessageSyncResult, token: MessageSyncToken) async throws {}

    @MainActor
    func endSync(_ token: MessageSyncToken) async {}

    @MainActor
    func appendOlderPage(_ page: MessagesPage, requestedBlockId: Int, conversationId: Int) async throws -> Bool {
        false
    }

    @MainActor
    func applyEdited(_ message: Message) async {
        editedMessages.append(message)
        await onApplyEdited?()
    }

    @MainActor
    @discardableResult
    func applySent(_ message: Message) async -> SentMessageWriteResult {
        await onApplySent?()
        guard stubbedApplySentResult == .written else { return stubbedApplySentResult }
        sentMessages.append(message)
        return .written
    }
}
