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
    /// Превью последнего сообщения; пустая строка — сообщений в переписке нет.
    let preview: String
    /// Время, когда переписка последний раз поднялась, в формате ленты сообщений.
    let time: String

    init(id: Int, title: String, isTitlePlaceholder: Bool = false, avatarURL: URL?, preview: String = "", time: String = "") {
        self.id = id
        self.title = title
        self.isTitlePlaceholder = isTitlePlaceholder
        self.avatarURL = avatarURL
        self.preview = preview
        self.time = time
    }
}

extension ChatRowDisplayModel {
    /// Собирает строку списка: у группы — её название и аватар, у личной переписки — имя и аватар собеседника
    /// из кэша пользователей. Пока собеседник не загружен, заголовок — заглушка; если его нет на сервере —
    /// текст об удалённом пользователе. Если нет ни названия, ни собеседника (например, тип переписки клиенту
    /// ещё не известен), строка получает запасной заголовок — она не должна выглядеть пустой.
    /// Превью — текст последнего сообщения (для неизвестного типа и сообщения без текста — «Сообщение»),
    /// время — когда переписка последний раз поднялась.
    /// - Parameters:
    ///   - conversation: переписка из ответа сервера или БД.
    ///   - opponent: собеседник из кэша по `opponentUserId`; `nil` — у переписки нет собеседника.
    ///   - timeFormatter: формат времени ленты сообщений.
    @MainActor
    init(conversation: Conversation, opponent: CachedUser?, timeFormatter: MessageTimeFormatter) {
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
            avatarURL: avatar.map { $0.smallURL ?? $0.url },
            preview: Self.preview(for: conversation.lastMessage),
            time: timeFormatter.string(from: conversation.positionUpdatedAt.date)
        )
    }

    /// Превью последнего сообщения.
    /// - Parameter lastMessage: последнее сообщение; `nil` — сообщений нет.
    /// - Returns: пустая строка, если сообщений нет; «Сообщение», если показать текст нельзя.
    @MainActor
    private static func preview(for lastMessage: LastMessage?) -> String {
        guard let lastMessage else { return "" }
        guard lastMessage.type != .unknown, let text = lastMessage.text else { return ChatListStrings.rowMessage }
        return text
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
