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
    /// `true` — собеседник ещё не загружен: вместо `title` показывается заглушка.
    let isTitlePlaceholder: Bool
    /// Аватар для списка — уменьшенная копия, если она есть. `nil` — аватар не установлен.
    let avatarURL: URL?

    init(id: Int, title: String, isTitlePlaceholder: Bool = false, avatarURL: URL?) {
        self.id = id
        self.title = title
        self.isTitlePlaceholder = isTitlePlaceholder
        self.avatarURL = avatarURL
    }
}

extension ChatRowDisplayModel {
    /// Собирает строку списка: у группы — её название и аватар, у личной переписки — имя и аватар собеседника
    /// из кэша пользователей. Пока собеседник не загружен, заголовок — заглушка; если его нет на сервере —
    /// текст об удалённом пользователе. Если нет ни названия, ни собеседника (например, тип переписки клиенту
    /// ещё не известен), строка получает запасной заголовок — она не должна выглядеть пустой.
    /// - Parameters:
    ///   - conversation: переписка из ответа сервера или БД.
    ///   - opponent: собеседник из кэша по `opponentUserId`; `nil` — у переписки нет собеседника.
    @MainActor
    init(conversation: Conversation, opponent: CachedUser?) {
        let opponentUser: User?
        if case let .loaded(user) = opponent {
            opponentUser = user
        } else {
            opponentUser = nil
        }
        let avatar = conversation.avatar ?? opponentUser?.avatar
        self.init(
            id: conversation.id,
            title: conversation.name ?? Self.opponentTitle(for: opponent) ?? ChatListStrings.rowUntitled,
            isTitlePlaceholder: conversation.name == nil && opponent == .pending,
            avatarURL: avatar.map { $0.smallURL ?? $0.url }
        )
    }

    /// Заголовок по собеседнику.
    /// - Parameter opponent: собеседник из кэша; `nil` — собеседника нет.
    /// - Returns: `nil`, если собеседника нет.
    @MainActor
    private static func opponentTitle(for opponent: CachedUser?) -> String? {
        switch opponent {
        case let .loaded(user): return user.name
        case .pending: return ChatListStrings.rowLoading
        case .notFound: return ChatListStrings.rowDeletedUser
        case nil: return nil
        }
    }
}
