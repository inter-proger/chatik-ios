//
//  ConversationNavigatorMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок навигатора: открытые переписки задаёт тест, открытия запоминаются.
@MainActor
final class ConversationNavigatorMock: ConversationNavigating {
    /// Открытые переписки.
    var openConversationIds: Set<Int> = []
    private(set) var openRequests: [Int] = []
    /// Регистрации по порядку.
    private(set) var registrations: [(token: UUID, router: ConversationOpening, sceneId: UUID?)] = []
    /// Снятые регистрации по порядку.
    private(set) var unregisteredTokens: [UUID] = []

    func register(_ router: ConversationOpening, sceneId: UUID?) -> UUID {
        let token = UUID()
        registrations.append((token, router, sceneId))
        return token
    }

    func unregister(_ token: UUID) {
        unregisteredTokens.append(token)
    }

    func isConversationOpen(_ conversationId: Int) -> Bool {
        openConversationIds.contains(conversationId)
    }

    func openConversation(id: Int) {
        openRequests.append(id)
    }
}

/// Мок роутера сцены: открытая переписка задаётся тестом, открытия запоминаются.
@MainActor
final class ConversationOpeningMock: ConversationOpening {
    var openedConversationId: Int?
    private(set) var opened: [Conversation] = []

    func openConversation(_ conversation: Conversation) {
        opened.append(conversation)
        openedConversationId = conversation.conversationId
    }
}
