//
//  RealtimeEvent+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension RealtimeEvent {
    /// `received` с превью, собранным из самого сообщения.
    /// - Parameter message: новое сообщение.
    static func received(_ message: Message) -> RealtimeEvent {
        .messageReceived(message, LastMessage(message: message))
    }

    /// `edited` с превью, собранным из самого сообщения, — отредактировано последнее сообщение переписки.
    /// - Parameter message: отредактированное сообщение.
    static func edited(_ message: Message) -> RealtimeEvent {
        .messageEdited(message, LastMessage(message: message))
    }
}
