//
//  MessageNotificationServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок уведомлений о сообщениях: запоминает вызовы.
@MainActor
final class MessageNotificationServiceMock: MessageNotificationServiceProtocol {
    private(set) var startCallCount = 0
    private(set) var openedConversationIds: [Int] = []
    /// Вызывается в `start()` — чтобы проверить порядок запуска.
    var onStart: (() -> Void)?

    func start() {
        startCallCount += 1
        onStart?()
    }

    func conversationDidOpen(_ conversationId: Int) {
        openedConversationIds.append(conversationId)
    }
}
