//
//  MessageReaderDisplayModel.swift
//  Chatik
//

import Foundation

/// Строка списка прочитавших сообщение в готовом для отображения виде.
struct MessageReaderDisplayModel: Identifiable, Equatable, Sendable {
    /// Идентификатор участника.
    let id: Int
    let name: String
    /// `true` — участник ещё не загружен: вместо `name` показывается заглушка.
    let isPlaceholder: Bool
    /// Уменьшенная копия аватара; `nil` — показывается изображение по умолчанию.
    let avatarURL: URL?
}

extension MessageReaderDisplayModel {
    /// Собирает строку по состоянию участника в кэше — с теми же текстами, что у отправителей в ленте.
    /// - Parameters:
    ///   - userId: участник.
    ///   - cachedUser: участник из кэша пользователей.
    @MainActor
    init(userId: Int, cachedUser: CachedUser) {
        let sender = MessageSenderDisplayModel(cachedUser: cachedUser, strings: .current)
        self.init(id: userId, name: sender.name, isPlaceholder: sender.isPlaceholder, avatarURL: sender.avatarURL)
    }
}
