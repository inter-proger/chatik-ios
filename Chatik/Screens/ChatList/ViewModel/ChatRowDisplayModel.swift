//
//  ChatRowDisplayModel.swift
//  Chatik
//

import SwiftUI

/// Превью строки списка чатов.
enum ChatRowPreview: Equatable {
    /// Текст последнего сообщения; «Новый чат» — сообщений нет; пустая строка — строка-заглушка без данных.
    case message(String)
    /// Черновик, готовый к показу: цветной префикс «Черновик:», пробел и текст в одну строку.
    case draft(AttributedString)
}

/// Переписка в списке чатов в готовом для отображения виде.
struct ChatRowDisplayModel: Identifiable, Equatable {
    let id: Int
    /// Название группы либо имя собеседника личной переписки.
    let title: String
    /// `true` — собеседник ещё не загружен: вместо `title` показывается заглушка.
    let isTitlePlaceholder: Bool
    /// Аватар для списка — уменьшенная копия, если она есть. `nil` — аватар не установлен.
    let avatarURL: URL?
    /// Превью: черновик, если он есть, иначе последнее сообщение.
    let preview: ChatRowPreview
    /// Время, когда переписка последний раз поднялась, в формате ленты сообщений.
    let time: String

    init(id: Int, title: String, isTitlePlaceholder: Bool = false, avatarURL: URL?, preview: ChatRowPreview = .message(""), time: String = "") {
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
    /// Превью — черновик, если он есть, иначе текст последнего сообщения (для неизвестного типа и сообщения
    /// без текста — «Сообщение», для переписки без сообщений — «Новый чат»), время — когда переписка последний раз поднялась (черновик его не меняет).
    /// - Parameters:
    ///   - conversation: переписка из ответа сервера или БД.
    ///   - opponent: собеседник из кэша по `opponentUserId`; `nil` — у переписки нет собеседника.
    ///   - draft: черновик переписки; `nil` — черновика нет.
    ///   - timeFormatter: формат времени ленты сообщений.
    @MainActor
    init(conversation: Conversation, opponent: CachedUser?, draft: String?, timeFormatter: MessageTimeFormatter) {
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
            preview: draft.map { .draft(Self.draftPreview($0)) } ?? .message(Self.preview(for: conversation.lastMessage)),
            time: timeFormatter.string(from: conversation.positionUpdatedAt.date)
        )
    }

    /// Превью последнего сообщения.
    /// - Parameter lastMessage: последнее сообщение; `nil` — сообщений нет.
    /// - Returns: «Новый чат», если сообщений нет; «Сообщение», если показать текст нельзя.
    @MainActor
    private static func preview(for lastMessage: LastMessage?) -> String {
        guard let lastMessage else { return ChatListStrings.rowNoMessages }
        guard lastMessage.type != .unknown, let text = lastMessage.text else { return ChatListStrings.rowMessage }
        return text
    }

    /// Сколько первых символов черновика попадает в превью: строка показывает одну строку текста, а длинный
    /// вставленный текст не должен обрабатываться целиком при каждой пересборке списка.
    static let draftPreviewLength = 200

    /// Превью черновика: цветной префикс «Черновик:», пробел и текст в одну строку — переводы строк и повторяющиеся
    /// пробельные символы заменены одним пробелом, края обрезаны по `MessageTextValidator.trimmedCharacters` —
    /// как и при решении, пуст ли черновик. Иначе в строке был бы виден только первый абзац.
    /// - Parameter draft: непустой черновик.
    @MainActor
    static func draftPreview(_ draft: String) -> AttributedString {
        let trimmed = MessageTextValidator.trimmedCharacters
        let text = draft.drop { $0.unicodeScalars.allSatisfy(trimmed.contains) }
            .prefix(draftPreviewLength)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: trimmed)
        var prefix = AttributedString(ChatListStrings.rowDraftPrefix)
        prefix.foregroundColor = Color.draftLabel
        return prefix + AttributedString(" " + text)
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
