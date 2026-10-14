//
//  Message+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension Message {
    /// Неотредактированное текстовое сообщение — типовой ответ `/messages/send`.
    static let stub = Message(
        messageId: 15,
        clientId: "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14",
        conversationId: 1,
        blockId: 2,
        senderId: 1,
        type: .text,
        text: "Привет!",
        isEdited: false,
        createdAt: .stub,
        updatedAt: .stub
    )

    /// То же сообщение после редактирования — типовой ответ `/messages/edit`.
    static let editedStub = Message(
        messageId: 15,
        clientId: "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14",
        conversationId: 1,
        blockId: 2,
        senderId: 1,
        type: .text,
        text: "Привет всем!",
        isEdited: true,
        createdAt: .stub,
        updatedAt: .stub(60_000)
    )
}

extension Message {
    /// Текстовое сообщение с заданными полями; остальные — как у `stub`.
    /// - Parameters:
    ///   - id: `messageId`.
    ///   - conversationId: переписка.
    ///   - senderId: отправитель.
    ///   - text: текст.
    ///   - clientId: идентификатор клиента-отправителя; по умолчанию — `client-<id>`.
    ///   - createdAt: время отправки; по умолчанию — как у `stub`.
    static func make(
        id: Int,
        conversationId: Int = 1,
        senderId: Int = 1,
        text: String = "Привет!",
        clientId: String? = nil,
        createdAt: ServerTime = stub.createdAt
    ) -> Message {
        Message(
            messageId: id,
            clientId: clientId ?? "client-\(id)",
            conversationId: conversationId,
            blockId: 1,
            senderId: senderId,
            type: .text,
            text: text,
            isEdited: false,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
