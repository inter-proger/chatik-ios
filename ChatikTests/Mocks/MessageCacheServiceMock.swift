//
//  MessageCacheServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок кэша сообщений для очереди отправки: запоминает отправленные сообщения; остальное — заглушки.
@MainActor
final class MessageCacheServiceMock: MessageCacheServiceProtocol {
    /// Сообщения, переданные в `applySent`, по порядку.
    private(set) var sentMessages: [Message] = []
    /// Вызывается внутри `applySent` до записи — пока запись гарантированно выполняется.
    var onApplySent: (@MainActor () async -> Void)?

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
    func applySent(_ message: Message) async {
        await onApplySent?()
        sentMessages.append(message)
    }
}
