//
//  ConversationPositionUpdatingMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок списка чатов для очереди отправки: запоминает сообщения, по которым поднималась переписка.
@MainActor
final class ConversationPositionUpdatingMock: ConversationPositionUpdating {
    private(set) var sentMessages: [Message] = []

    func applySentMessage(_ message: Message) {
        sentMessages.append(message)
    }
}
