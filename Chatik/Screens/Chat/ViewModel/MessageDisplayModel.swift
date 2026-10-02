//
//  MessageDisplayModel.swift
//  Chatik
//

import Foundation

/// Сообщение переписки в готовом для отображения виде.
struct MessageDisplayModel: Identifiable, Equatable {
    let id: Int
    /// Текст сообщения; для неизвестного типа — пояснение, что сообщение не поддерживается.
    let text: String
    /// `true` — тип сообщения неизвестен клиенту, `text` — пояснение, а не содержимое.
    let isUnsupported: Bool
    /// `true` — сообщение отправил текущий пользователь.
    let isOutgoing: Bool
    /// Имя отправителя — только у входящих сообщений групповой переписки. `nil` — имя не показывается.
    let senderName: String?
    /// `true` — отправитель ещё не загружен: вместо `senderName` показывается заглушка.
    let isSenderPlaceholder: Bool
    /// Время отправки: только время для сегодняшних сообщений, иначе дата и время.
    let time: String
    /// Пометка «изменено»; `nil` — сообщение не редактировалось.
    let editedLabel: String?
}

/// Как показать сообщение — общие для всех сообщений экрана параметры.
struct MessageDisplayContext {
    /// Текущий пользователь: его сообщения показываются исходящими. `nil` — сессии нет, все сообщения входящие.
    let currentUserId: Int?
    /// `true` — переписка групповая: у входящих сообщений показывается имя отправителя.
    let showsSenderNames: Bool
    /// Язык форматирования времени.
    let locale: Locale
    /// Календарь (с часовым поясом), по которому определяется «сегодня».
    let calendar: Calendar
    /// Текущее время.
    let now: Date
}

extension MessageDisplayModel {
    /// Собирает сообщение для отображения.
    /// - Parameters:
    ///   - message: сообщение из ответа сервера или БД.
    ///   - sender: отправитель из кэша пользователей; `nil` — имя отправителя не нужно.
    ///   - context: общие параметры отображения.
    @MainActor
    init(message: Message, sender: CachedUser?, context: MessageDisplayContext) {
        let isOutgoing = message.senderId == context.currentUserId
        let showsSender = context.showsSenderNames && !isOutgoing
        let isUnsupported = message.type == .unknown
        self.init(
            id: message.id,
            text: isUnsupported ? ChatStrings.messageUnsupported : message.text,
            isUnsupported: isUnsupported,
            isOutgoing: isOutgoing,
            senderName: showsSender ? Self.senderName(for: sender) : nil,
            isSenderPlaceholder: showsSender && sender == .pending,
            time: Self.formattedTime(message.createdAt, context: context),
            editedLabel: message.isEdited ? ChatStrings.messageEdited : nil
        )
    }

    /// Имя отправителя по состоянию в кэше.
    /// - Parameter sender: отправитель из кэша; `nil` — неизвестен.
    @MainActor
    private static func senderName(for sender: CachedUser?) -> String {
        switch sender {
        case let .loaded(user): return user.name
        case .pending, nil: return ChatStrings.userLoading
        case .notFound: return ChatStrings.userDeleted
        }
    }

    /// Форматирует время отправки: сегодняшнее — только время, в этом году — день, месяц и время,
    /// раньше — ещё и год.
    /// - Parameters:
    ///   - date: время отправки.
    ///   - context: язык, календарь и текущее время.
    static func formattedTime(_ date: Date, context: MessageDisplayContext) -> String {
        var style = Date.FormatStyle(locale: context.locale, calendar: context.calendar, timeZone: context.calendar.timeZone)
            .hour().minute()
        guard !context.calendar.isDate(date, inSameDayAs: context.now) else { return date.formatted(style) }
        style = style.day().month(.abbreviated)
        guard context.calendar.isDate(date, equalTo: context.now, toGranularity: .year) else {
            return date.formatted(style.year())
        }
        return date.formatted(style)
    }
}
