//
//  ChatRowDisplayModel.swift
//  Chatik
//

import SwiftUI

/// Превью строки списка чатов.
enum ChatRowPreview: Equatable {
    /// Текст последнего сообщения; «Новый чат» — сообщений нет; пустая строка — строка-заглушка без данных.
    case message(String)
    /// Локальное состояние переписки, готовое к показу: цветной префикс («Черновик:», «Не отправлено:»), пробел
    /// и текст в одну строку.
    case labeled(AttributedString)
}

/// Локальное состояние переписки, вытесняющее последнее сообщение в превью строки.
enum ChatRowLocalPreview: Equatable {
    /// Незавершённое редактирование своего сообщения — текст правки в строке не показывается.
    case editing
    /// Последнее неотправленное сообщение.
    case failed(String)
    /// Черновик.
    case draft(String)
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
    /// Превью: неотправленное сообщение или черновик, если они есть, иначе последнее сообщение.
    let preview: ChatRowPreview
    /// Время, когда переписка последний раз поднялась, в формате ленты сообщений.
    let time: String
    /// Счётчик непрочитанных: точное число до 99, выше — «99+». `nil` — непрочитанных нет, капсула не показывается.
    let unreadCountText: String?
    /// Подпись счётчика для VoiceOver — с точным числом.
    let unreadAccessibilityLabel: String?

    init(
        id: Int,
        title: String,
        isTitlePlaceholder: Bool = false,
        avatarURL: URL?,
        preview: ChatRowPreview = .message(""),
        time: String = "",
        unreadCountText: String? = nil,
        unreadAccessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isTitlePlaceholder = isTitlePlaceholder
        self.avatarURL = avatarURL
        self.preview = preview
        self.time = time
        self.unreadCountText = unreadCountText
        self.unreadAccessibilityLabel = unreadAccessibilityLabel
    }
}

extension ChatRowDisplayModel {
    /// Собирает строку списка: у группы — её название и аватар, у личной переписки — имя и аватар собеседника
    /// из кэша пользователей. Пока собеседник не загружен, заголовок — заглушка; если его нет на сервере —
    /// текст об удалённом пользователе. Если нет ни названия, ни собеседника (например, тип переписки клиенту
    /// ещё не известен), строка получает запасной заголовок — она не должна выглядеть пустой.
    /// Превью — локальное состояние (неотправленное сообщение или черновик), если оно есть, иначе текст последнего
    /// сообщения (для неизвестного типа и сообщения без текста — «Сообщение», для переписки без сообщений —
    /// «Новый чат»), время — когда переписка последний раз поднялась (локальное состояние его не меняет).
    /// - Parameters:
    ///   - conversation: переписка из ответа сервера или БД.
    ///   - opponent: собеседник из кэша по `opponentUserId`; `nil` — у переписки нет собеседника.
    ///   - localPreview: неотправленное сообщение или черновик переписки; `nil` — нет ни того, ни другого.
    ///   - unreadCount: непрочитанные для показа — с учётом оптимистичной отметки прочтения.
    ///   - timeFormatter: формат времени ленты сообщений.
    @MainActor
    init(
        conversation: Conversation,
        opponent: CachedUser?,
        localPreview: ChatRowLocalPreview?,
        unreadCount: Int,
        timeFormatter: MessageTimeFormatter
    ) {
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
            preview: localPreview.map { .labeled(Self.localPreview($0)) } ?? .message(Self.preview(for: conversation.lastMessage)),
            time: timeFormatter.string(from: conversation.positionUpdatedAt.date),
            unreadCountText: UnreadCountFormatter.text(for: unreadCount),
            unreadAccessibilityLabel: UnreadCountFormatter.accessibilityLabel(for: unreadCount)
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

    /// Сколько первых символов черновика или неотправленного сообщения попадает в превью: строка показывает одну
    /// строку текста, а длинный вставленный текст не должен обрабатываться целиком при каждой пересборке списка.
    static let localPreviewLength = 200

    /// Превью локального состояния переписки: «Не отправлено:» или «Черновик:» своим цветом и текст либо
    /// «Редактирование активно» целиком цветом черновика.
    /// - Parameter localPreview: редактирование, неотправленное сообщение или черновик.
    @MainActor
    static func localPreview(_ localPreview: ChatRowLocalPreview) -> AttributedString {
        switch localPreview {
        case .editing:
            labeledPreview(prefix: ChatListStrings.rowEditing, color: .draftLabel, text: nil)
        case let .failed(text):
            labeledPreview(prefix: ChatListStrings.rowFailedPrefix, color: .chatListFailedLabel, text: text)
        case let .draft(text):
            labeledPreview(prefix: ChatListStrings.rowDraftPrefix, color: .draftLabel, text: text)
        }
    }

    /// Превью с цветным префиксом: префикс, пробел и текст в одну строку (`SingleLineText`).
    /// - Parameters:
    ///   - prefix: префикс — «Черновик:», «Не отправлено:» или фраза целиком.
    ///   - color: цвет префикса; текст остаётся без цвета.
    ///   - text: непустой текст; `nil` — превью из одного префикса, без пробела после него.
    @MainActor
    private static func labeledPreview(prefix: String, color: Color, text: String?) -> AttributedString {
        var label = AttributedString(prefix)
        label.foregroundColor = color
        guard let text else { return label }
        return label + AttributedString(" " + SingleLineText.make(text, maxLength: localPreviewLength))
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
