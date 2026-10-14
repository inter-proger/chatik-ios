//
//  Conversation+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension ServerTime {
    /// Типовое время стабов — 1 октября 2026, 09:20:00.000 UTC.
    static let stub = ServerTime(milliseconds: 1_790_846_400_000)

    /// Время, сдвинутое от `stub` на указанное число миллисекунд.
    /// - Parameter offset: сдвиг в миллисекундах.
    static func stub(_ offset: Int64) -> ServerTime {
        stub.adding(milliseconds: offset)
    }
}

extension Conversation {
    /// Личная переписка двух пользователей без сообщений — типовой ответ `/conversations/createSingle`.
    static let singleStub = Conversation(
        conversationId: 1,
        type: .single,
        memberIds: [1, 2],
        name: nil,
        avatar: nil,
        opponentUserId: 2,
        lastMessage: nil,
        positionUpdatedAt: .stub,
        updatedInfoAt: .stub
    )

    /// Групповая переписка с названием, аватаром и последним сообщением — типовой элемент списка переписок.
    static let groupStub = Conversation(
        conversationId: 2,
        type: .group,
        memberIds: [1, 2, 3],
        name: "Команда",
        avatar: .stub,
        opponentUserId: nil,
        lastMessage: LastMessage(messageId: 15, type: .text, text: "Привет!", updatedAt: .stub),
        positionUpdatedAt: .stub,
        updatedInfoAt: .stub
    )

    /// Групповая переписка с заданными id и позицией; остальные поля — как у `groupStub`, без последнего сообщения.
    /// - Parameters:
    ///   - id: `conversationId`.
    ///   - position: `positionUpdatedAt`; по умолчанию — `ServerTime.stub`.
    ///   - updatedInfoAt: `updatedInfoAt`; по умолчанию — `ServerTime.stub`.
    static func make(id: Int, position: ServerTime = .stub, updatedInfoAt: ServerTime = .stub) -> Conversation {
        Conversation(
            conversationId: id,
            type: .group,
            memberIds: [1, 2],
            name: "Чат \(id)",
            avatar: nil,
            opponentUserId: nil,
            lastMessage: nil,
            positionUpdatedAt: position,
            updatedInfoAt: updatedInfoAt
        )
    }
}

extension Conversation {
    /// Копия переписки с другой позицией и последним сообщением.
    /// - Parameters:
    ///   - position: `positionUpdatedAt`.
    ///   - lastMessage: последнее сообщение.
    func with(position: ServerTime, lastMessage: LastMessage?) -> Conversation {
        Conversation(
            conversationId: conversationId, type: type, memberIds: memberIds, name: name, avatar: avatar,
            opponentUserId: opponentUserId, lastMessage: lastMessage, positionUpdatedAt: position, updatedInfoAt: updatedInfoAt
        )
    }

    /// Копия переписки с другой информацией.
    /// - Parameters:
    ///   - name: название.
    ///   - updatedInfoAt: версия информации.
    func with(name: String?, updatedInfoAt: ServerTime) -> Conversation {
        Conversation(
            conversationId: conversationId, type: type, memberIds: memberIds, name: name, avatar: avatar,
            opponentUserId: opponentUserId, lastMessage: lastMessage, positionUpdatedAt: positionUpdatedAt, updatedInfoAt: updatedInfoAt
        )
    }
}

extension LastMessage {
    /// Текстовое последнее сообщение.
    /// - Parameters:
    ///   - id: `messageId`.
    ///   - text: текст.
    ///   - updatedAt: версия текста; по умолчанию — `ServerTime.stub`.
    static func make(id: Int, text: String = "Привет!", updatedAt: ServerTime = .stub) -> LastMessage {
        LastMessage(messageId: id, type: .text, text: text, updatedAt: updatedAt)
    }
}
