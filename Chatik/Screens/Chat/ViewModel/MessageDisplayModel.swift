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
    /// Отправитель — только у первого сообщения серии подряд от одного отправителя: рядом с ним показываются
    /// аватар и имя. `nil` — сообщение продолжает серию, на месте аватара пустой отступ.
    let sender: MessageSenderDisplayModel?
    /// Время отправки: только время для сегодняшних сообщений, иначе дата и время.
    let time: String
    /// Пометка «изменено»; `nil` — сообщение не редактировалось.
    let editedLabel: String?
}

/// Отправитель сообщения в готовом для отображения виде.
struct MessageSenderDisplayModel: Equatable {
    let name: String
    /// `true` — отправитель ещё не загружен: вместо `name` показывается заглушка.
    let isPlaceholder: Bool
    /// Уменьшенная копия аватара; `nil` — показывается изображение по умолчанию.
    let avatarURL: URL?
}

/// Как показать сообщение — общие для всех сообщений экрана параметры.
struct MessageDisplayContext {
    /// Текущий пользователь: его сообщения показываются исходящими. `nil` — сессии нет, все сообщения входящие.
    let currentUserId: Int?
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
    ///   - sender: отправитель из кэша пользователей; `nil` — сообщение продолжает серию, аватар и имя не нужны.
    ///   - context: общие параметры отображения.
    @MainActor
    init(message: Message, sender: CachedUser?, context: MessageDisplayContext) {
        let isUnsupported = message.type == .unknown
        self.init(
            id: message.id,
            text: isUnsupported ? ChatStrings.messageUnsupported : message.text,
            isUnsupported: isUnsupported,
            isOutgoing: message.senderId == context.currentUserId,
            sender: sender.map(MessageSenderDisplayModel.init(cachedUser:)),
            time: Self.formattedTime(message.createdAt, context: context),
            editedLabel: message.isEdited ? ChatStrings.messageEdited : nil
        )
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

extension MessageSenderDisplayModel {
    /// Собирает отправителя по состоянию в кэше: загруженный — имя и аватар, загружается — заглушка,
    /// удалён — текст об удалённом пользователе.
    /// - Parameter cachedUser: отправитель из кэша пользователей.
    @MainActor
    init(cachedUser: CachedUser) {
        switch cachedUser {
        case let .loaded(user):
            self.init(name: user.name, isPlaceholder: false, avatarURL: user.avatar.map { $0.smallURL ?? $0.url })
        case .pending:
            self.init(name: ChatStrings.userLoading, isPlaceholder: true, avatarURL: nil)
        case .notFound:
            self.init(name: ChatStrings.userDeleted, isPlaceholder: false, avatarURL: nil)
        }
    }
}
