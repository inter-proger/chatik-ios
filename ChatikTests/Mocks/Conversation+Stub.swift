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
        opponentUserId: 2
    )

    /// Групповая переписка с названием и аватаром — типовой элемент списка переписок.
    static let groupStub = Conversation(
        conversationId: 2,
        type: .group,
        memberIds: [1, 2, 3],
        name: "Команда",
        avatar: .stub,
        opponentUserId: nil
    )
}
