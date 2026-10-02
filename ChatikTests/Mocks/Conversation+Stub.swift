//
//  Conversation+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension Conversation {
    /// Личная переписка двух пользователей — типовой ответ `/conversations/createSingle`.
    static let singleStub = Conversation(
        conversationId: 1,
        type: .single,
        memberIds: [1, 2],
        name: nil,
        avatar: nil,
        opponentUserId: 2,
        updatedAt: Date(timeIntervalSince1970: 1_790_846_400)
    )

    /// Групповая переписка с названием и аватаром — типовой элемент списка переписок.
    static let groupStub = Conversation(
        conversationId: 2,
        type: .group,
        memberIds: [1, 2, 3],
        name: "Команда",
        avatar: .stub,
        opponentUserId: nil,
        updatedAt: Date(timeIntervalSince1970: 1_790_846_400)
    )
}

extension Conversation {
    /// Копия переписки с другим временем изменения — более новая или более старая версия той же переписки.
    /// - Parameter updatedAt: время изменения.
    func with(updatedAt: Date) -> Conversation {
        Conversation(
            conversationId: conversationId,
            type: type,
            memberIds: memberIds,
            name: name,
            avatar: avatar,
            opponentUserId: opponentUserId,
            updatedAt: updatedAt
        )
    }
}
