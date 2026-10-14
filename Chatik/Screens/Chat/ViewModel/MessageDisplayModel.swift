//
//  MessageDisplayModel.swift
//  Chatik
//

import Foundation

/// Состояние доставки сообщения.
enum MessageDeliveryState: Equatable, Sendable {
    /// Сообщение есть на сервере.
    case delivered
    /// Отправляется: сервер ещё не ответил.
    case sending
    /// Не отправлено: по тапу можно повторить отправку или удалить сообщение.
    case failed
}

/// Сообщение переписки в готовом для отображения виде.
struct MessageDisplayModel: Identifiable, Equatable, Sendable {
    /// Отправитель и `clientId`: у неотправленного сообщения и созданного из него серверного он один и тот же,
    /// поэтому при подтверждении отправки пузырь остаётся на месте, а не пересоздаётся.
    let id: MessageClientKey
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
    let deliveryState: MessageDeliveryState
    /// Описание состояния доставки для VoiceOver; `nil` — сообщение доставлено.
    let deliveryStateLabel: String?
}

/// Отправитель сообщения в готовом для отображения виде.
struct MessageSenderDisplayModel: Equatable, Sendable {
    let name: String
    /// `true` — отправитель ещё не загружен: вместо `name` показывается заглушка.
    let isPlaceholder: Bool
    /// Уменьшенная копия аватара; `nil` — показывается изображение по умолчанию.
    let avatarURL: URL?
}

/// Тексты ленты из локализации. Собираются на main (`ChatStrings`) и передаются значениями, чтобы сообщения
/// можно было собирать вне main.
struct MessageDisplayStrings: Equatable, Sendable {
    let unsupported: String
    let edited: String
    let sending: String
    let failed: String
    let userLoading: String
    let userDeleted: String

    /// Тексты на текущем языке приложения.
    @MainActor
    static var current: MessageDisplayStrings {
        MessageDisplayStrings(
            unsupported: ChatStrings.messageUnsupported,
            edited: ChatStrings.messageEdited,
            sending: ChatStrings.messageSending,
            failed: ChatStrings.messageFailed,
            userLoading: ChatStrings.userLoading,
            userDeleted: ChatStrings.userDeleted
        )
    }
}

/// Как показать сообщение — общие для всех сообщений экрана параметры.
struct MessageDisplayContext: Sendable {
    /// Текущий пользователь: его сообщения показываются исходящими. `nil` — сессии нет, все сообщения входящие.
    let currentUserId: Int?
    /// Язык форматирования времени.
    let locale: Locale
    /// Календарь (с часовым поясом), по которому определяется «сегодня».
    let calendar: Calendar
    /// Текущее время.
    let now: Date
    /// Тексты ленты.
    let strings: MessageDisplayStrings
}

extension MessageDisplayModel {
    /// Собирает сообщение для отображения.
    /// - Parameters:
    ///   - message: сообщение из ответа сервера или БД.
    ///   - sender: отправитель из кэша пользователей; `nil` — сообщение продолжает серию, аватар и имя не нужны.
    ///   - context: общие параметры отображения.
    init(message: Message, sender: CachedUser?, context: MessageDisplayContext) {
        let isUnsupported = message.type == .unknown
        self.init(
            id: message.clientKey,
            text: isUnsupported ? context.strings.unsupported : message.text,
            isUnsupported: isUnsupported,
            isOutgoing: message.senderId == context.currentUserId,
            sender: sender.map { MessageSenderDisplayModel(cachedUser: $0, strings: context.strings) },
            time: Self.formattedTime(message.createdAt.date, context: context),
            editedLabel: message.isEdited ? context.strings.edited : nil,
            deliveryState: .delivered,
            deliveryStateLabel: nil
        )
    }

    /// Собирает для отображения сообщение, ещё не подтверждённое сервером. Оно всегда исходящее; время —
    /// момент нажатия «Отправить».
    /// - Parameters:
    ///   - outgoing: сообщение очереди отправки.
    ///   - sender: отправитель (текущий пользователь); `nil` — сообщение продолжает серию.
    ///   - context: общие параметры отображения.
    init(outgoing: OutgoingMessage, sender: CachedUser?, context: MessageDisplayContext) {
        let deliveryState: MessageDeliveryState = outgoing.status == .failed ? .failed : .sending
        self.init(
            id: outgoing.clientKey,
            text: outgoing.text,
            isUnsupported: false,
            isOutgoing: true,
            sender: sender.map { MessageSenderDisplayModel(cachedUser: $0, strings: context.strings) },
            time: Self.formattedTime(outgoing.createdAt, context: context),
            editedLabel: nil,
            deliveryState: deliveryState,
            deliveryStateLabel: deliveryState == .failed ? context.strings.failed : context.strings.sending
        )
    }

    /// Форматирует время отправки в формате ленты (см. `MessageTimeFormatter`).
    /// - Parameters:
    ///   - date: время отправки.
    ///   - context: язык, календарь и текущее время.
    static func formattedTime(_ date: Date, context: MessageDisplayContext) -> String {
        MessageTimeFormatter(locale: context.locale, calendar: context.calendar, now: context.now).string(from: date)
    }
}

extension MessageSenderDisplayModel {
    /// Собирает отправителя по состоянию в кэше: загруженный — имя и аватар, загружается — заглушка,
    /// удалён — текст об удалённом пользователе.
    /// - Parameters:
    ///   - cachedUser: отправитель из кэша пользователей.
    ///   - strings: тексты ленты.
    init(cachedUser: CachedUser, strings: MessageDisplayStrings) {
        switch cachedUser {
        case let .loaded(user):
            self.init(name: user.name, isPlaceholder: false, avatarURL: user.avatar.map { $0.smallURL ?? $0.url })
        case .pending:
            self.init(name: strings.userLoading, isPlaceholder: true, avatarURL: nil)
        case .notFound:
            self.init(name: strings.userDeleted, isPlaceholder: false, avatarURL: nil)
        }
    }
}
