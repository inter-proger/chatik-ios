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
        updatedInfoAt: .stub,
        readState: .stub
    )

    /// Групповая переписка с названием, аватаром и последним сообщением — типовой элемент списка переписок.
    static let groupStub = Conversation(
        conversationId: 2,
        type: .group,
        memberIds: nil,
        name: "Команда",
        description: "Рабочие вопросы",
        avatar: .stub,
        opponentUserId: nil,
        lastMessage: LastMessage(messageId: 15, senderId: 1, type: .text, text: "Привет!", updatedAt: .stub),
        positionUpdatedAt: .stub,
        updatedInfoAt: .stub,
        readState: .stub
    )

    /// Групповая переписка с заданными id и позицией; остальные поля — как у `groupStub`, без последнего сообщения.
    /// - Parameters:
    ///   - id: `conversationId`.
    ///   - position: `positionUpdatedAt`; по умолчанию — `ServerTime.stub`.
    ///   - updatedInfoAt: `updatedInfoAt`; по умолчанию — `ServerTime.stub`.
    ///   - readState: прочтение; по умолчанию — всё прочитано на версии 1.
    static func make(
        id: Int,
        position: ServerTime = .stub,
        updatedInfoAt: ServerTime = .stub,
        readState: ConversationReadState = .stub
    ) -> Conversation {
        Conversation(
            conversationId: id,
            type: .group,
            memberIds: nil,
            name: "Чат \(id)",
            avatar: nil,
            opponentUserId: nil,
            lastMessage: nil,
            positionUpdatedAt: position,
            updatedInfoAt: updatedInfoAt,
            readState: readState
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
            opponentUserId: opponentUserId, lastMessage: lastMessage, positionUpdatedAt: position, updatedInfoAt: updatedInfoAt,
            readState: readState
        )
    }

    /// Копия переписки с другой информацией.
    /// - Parameters:
    ///   - name: название.
    ///   - updatedInfoAt: версия информации.
    func with(name: String?, updatedInfoAt: ServerTime) -> Conversation {
        Conversation(
            conversationId: conversationId, type: type, memberIds: memberIds, name: name, avatar: avatar,
            opponentUserId: opponentUserId, lastMessage: lastMessage, positionUpdatedAt: positionUpdatedAt, updatedInfoAt: updatedInfoAt,
            readState: readState
        )
    }

    /// Копия переписки с другим прочтением.
    /// - Parameter readState: прочтение.
    func with(readState: ConversationReadState) -> Conversation {
        Conversation(
            conversationId: conversationId, type: type, memberIds: memberIds, name: name, avatar: avatar,
            opponentUserId: opponentUserId, lastMessage: lastMessage, positionUpdatedAt: positionUpdatedAt, updatedInfoAt: updatedInfoAt,
            readState: readState
        )
    }
}

extension ConversationReadState {
    /// Всё прочитано на версии 1.
    static let stub = ConversationReadState(unreadCount: 0, lastReadMessageId: 0, changeVersion: 1)

    /// Прочтение с заданными полями.
    /// - Parameters:
    ///   - unread: `unreadCount`.
    ///   - lastRead: `lastReadMessageId`.
    ///   - version: `changeVersion`.
    static func make(unread: Int = 0, lastRead: Int = 0, version: Int) -> ConversationReadState {
        ConversationReadState(unreadCount: unread, lastReadMessageId: lastRead, changeVersion: version)
    }
}

extension ReadInfo {
    /// Прочтение переписки с заданными полями.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - lastRead: `lastReadMessageId`.
    ///   - unread: `unreadCount`.
    ///   - total: `totalUnreadCount`.
    ///   - version: `changeVersion`.
    static func make(conversationId: Int, lastRead: Int = 0, unread: Int = 0, total: Int = 0, version: Int) -> ReadInfo {
        ReadInfo(conversationId: conversationId, lastReadMessageId: lastRead, unreadCount: unread, totalUnreadCount: total, changeVersion: version)
    }
}

extension LastMessage {
    /// Текстовое последнее сообщение.
    /// - Parameters:
    ///   - id: `messageId`.
    ///   - text: текст.
    ///   - updatedAt: версия текста; по умолчанию — `ServerTime.stub`.
    static func make(id: Int, text: String = "Привет!", updatedAt: ServerTime = .stub) -> LastMessage {
        LastMessage(messageId: id, senderId: 1, type: .text, text: text, updatedAt: updatedAt)
    }
}
