//
//  ChatInputMode.swift
//  Chatik
//

import Foundation

/// Что делает поле ввода экрана переписки.
enum ChatInputMode: Equatable {
    /// Новое сообщение; текст поля — черновик.
    case compose
    /// Правка своего сообщения; текст поля — текст правки.
    /// - `messageId`: редактируемое сообщение.
    /// - `originalText`: текст сообщения на момент включения режима.
    case editing(messageId: Int, originalText: String)
}
