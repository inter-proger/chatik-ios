//
//  RealtimeEvent+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension RealtimeEvent {
    /// `received` с превью, собранным из самого сообщения.
    /// - Parameters:
    ///   - message: новое сообщение.
    ///   - readInfo: прочтение из события; по умолчанию — нет.
    static func received(_ message: Message, readInfo: ReadInfo? = nil) -> RealtimeEvent {
        .messageReceived(message, LastMessage(message: message), readInfo)
    }

    /// `edited` с превью, собранным из самого сообщения, — отредактировано последнее сообщение переписки.
    /// - Parameters:
    ///   - message: отредактированное сообщение.
    ///   - changeVersion: версия пользователя из события; по умолчанию — нет.
    static func edited(_ message: Message, changeVersion: Int? = nil) -> RealtimeEvent {
        .messageEdited(message, LastMessage(message: message), changeVersion: changeVersion)
    }
}
