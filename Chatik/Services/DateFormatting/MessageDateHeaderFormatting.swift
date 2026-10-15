//
//  MessageDateHeaderFormatting.swift
//  Chatik
//

import Foundation

/// Текст заголовка дня в ленте сообщений.
protocol MessageDateHeaderFormatting: Sendable {
    /// Форматирует дату заголовка.
    /// - Parameters:
    ///   - date: время любого сообщения этого дня.
    ///   - now: текущее время.
    func string(from date: Date, now: Date) -> String
}
