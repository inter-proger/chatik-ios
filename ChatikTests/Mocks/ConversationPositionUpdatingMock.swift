//
//  ConversationPositionUpdatingMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок списка чатов для очереди отправки и сервиса правок: запоминает сообщения, по которым поднималась переписка
/// или менялось превью.
@MainActor
final class ConversationPositionUpdatingMock: ConversationPositionUpdating {
    private(set) var sentMessages: [Message] = []
    /// Прочтение из ответов на отправку — в порядке `sentMessages`.
    private(set) var sentReadInfos: [ReadInfo?] = []
    private(set) var editedMessages: [(message: Message, lastMessage: LastMessage?)] = []
    /// Вызывается внутри `applyEditedMessage` — для проверки порядка вызовов.
    var onApplyEdited: (@MainActor () -> Void)?

    func applySentMessage(_ message: Message, readInfo: ReadInfo?) {
        sentMessages.append(message)
        sentReadInfos.append(readInfo)
    }

    func applyEditedMessage(_ message: Message, lastMessage: LastMessage?) {
        editedMessages.append((message, lastMessage))
        onApplyEdited?()
    }
}
