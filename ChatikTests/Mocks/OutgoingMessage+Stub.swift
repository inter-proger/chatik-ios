//
//  OutgoingMessage+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension OutgoingMessage {
    /// Неотправленное сообщение с заданными полями.
    /// - Parameters:
    ///   - clientId: идентификатор клиента.
    ///   - conversationId: переписка.
    ///   - senderId: отправитель.
    ///   - text: текст.
    ///   - createdAt: время отправки.
    ///   - status: состояние отправки.
    static func stub(
        clientId: String,
        conversationId: Int = 1,
        senderId: Int = 1,
        text: String = "Привет!",
        createdAt: Date = Date(timeIntervalSince1970: 1_790_846_400),
        status: OutgoingMessageStatus = .sending
    ) -> OutgoingMessage {
        OutgoingMessage(
            clientId: clientId,
            conversationId: conversationId,
            senderId: senderId,
            text: text,
            createdAt: createdAt,
            status: status
        )
    }
}
