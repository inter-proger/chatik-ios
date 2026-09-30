//
//  ChatRowDisplayModel.swift
//  Chatik
//

import Foundation

/// Переписка в списке чатов в готовом для отображения виде.
struct ChatRowDisplayModel: Identifiable, Equatable {
    let id: Int
    /// Название группы либо имя собеседника личной переписки.
    let title: String
    /// Аватар для списка — уменьшенная копия, если она есть. `nil` — аватар не установлен.
    let avatarURL: URL?
}

extension ChatRowDisplayModel {
    /// Собирает строку списка: у группы — её название и аватар, у личной переписки — имя и аватар собеседника.
    /// Если сервер не прислал ни того, ни другого (например, тип переписки клиенту ещё не известен),
    /// строка получает запасной заголовок — она не должна выглядеть пустой.
    /// - Parameter conversation: переписка из ответа сервера.
    @MainActor
    init(conversation: Conversation) {
        id = conversation.id
        title = conversation.name ?? conversation.opponentUser?.name ?? ChatListStrings.rowUntitled
        let avatar = conversation.avatar ?? conversation.opponentUser?.avatar
        avatarURL = avatar.map { $0.smallURL ?? $0.url }
    }
}
