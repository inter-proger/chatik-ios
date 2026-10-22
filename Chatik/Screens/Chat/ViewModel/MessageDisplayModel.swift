//
//  MessageDisplayModel.swift
//  Chatik
//

import Foundation

/// Состояние доставки сообщения.
enum MessageDeliveryState: Equatable, Sendable {
    /// Сообщение есть на сервере; у своего — одна галочка.
    case delivered
    /// Своё сообщение прочитано хотя бы одним другим участником — две галочки.
    case read
    /// Отправляется: сервер ещё не ответил.
    case sending
    /// Не отправлено: меню сообщения предлагает повторить отправку или удалить сообщение.
    case failed
}

/// Действие с сообщением из меню сообщения.
enum MessageAction: Equatable, Sendable {
    /// Редактировать своё доставленное сообщение.
    case edit
    /// Повторить отправку неотправленного сообщения.
    case retrySending
    /// Удалить неотправленное сообщение.
    case deleteUnsent
    /// Показать, кто из участников групповой переписки прочитал сообщение.
    case readers
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
    /// Время отправки на сервере, только время без даты — дату показывает заголовок дня. `nil` — сообщения ещё
    /// нет на сервере: на месте времени показывается состояние доставки.
    let time: String?
    /// Пометка «изменено»; `nil` — сообщение не редактировалось.
    let editedLabel: String?
    let deliveryState: MessageDeliveryState
    /// Описание состояния доставки для VoiceOver; `nil` — у сообщения нет состояния доставки (чужое).
    let deliveryStateLabel: String?
    /// Действия меню сообщения; пусто — меню нет.
    let actions: [MessageAction]
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
    let delivered: String
    let read: String
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
            delivered: ChatStrings.messageDelivered,
            read: ChatStrings.messageRead,
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
    /// Календарь (с часовым поясом), по которому сообщения делятся на дни.
    let calendar: Calendar
    /// Текущее время.
    let now: Date
    /// Тексты ленты.
    let strings: MessageDisplayStrings
    /// Заголовки дней на языке `locale`.
    let dateHeaderFormatter: any MessageDateHeaderFormatting
    /// Тип переписки: «Кем прочитано» есть только в групповой.
    let conversationType: ConversationType
    /// Порог прочтения другими участниками: свои сообщения с id не больше него прочитаны. `nil` — меты нет,
    /// две галочки не показываются.
    let readUpTo: Int?
}

extension MessageDisplayModel {
    /// Собирает сообщение для отображения.
    /// - Parameters:
    ///   - message: сообщение из ответа сервера или БД.
    ///   - sender: отправитель из кэша пользователей; `nil` — сообщение продолжает серию, аватар и имя не нужны.
    ///   - context: общие параметры отображения.
    init(message: Message, sender: CachedUser?, context: MessageDisplayContext) {
        let isUnsupported = message.type == .unknown
        let isOutgoing = message.senderId == context.currentUserId
        let deliveryState = Self.deliveryState(for: message, isOutgoing: isOutgoing, context: context)
        self.init(
            id: message.clientKey,
            text: isUnsupported ? context.strings.unsupported : message.text,
            isUnsupported: isUnsupported,
            isOutgoing: isOutgoing,
            sender: sender.map { MessageSenderDisplayModel(cachedUser: $0, strings: context.strings) },
            time: Self.formattedTime(message.createdAt.date, context: context),
            editedLabel: message.isEdited ? context.strings.edited : nil,
            deliveryState: deliveryState,
            deliveryStateLabel: isOutgoing ? (deliveryState == .read ? context.strings.read : context.strings.delivered) : nil,
            actions: Self.actions(for: message, context: context)
        )
    }

    /// Состояние серверного сообщения: своё с id не больше порога прочтения — прочитано, остальные — доставлены.
    /// Без меты (`readUpTo == nil`) две галочки не показываются.
    /// - Parameters:
    ///   - message: сообщение с сервера.
    ///   - isOutgoing: сообщение текущего пользователя.
    ///   - context: общие параметры отображения.
    static func deliveryState(for message: Message, isOutgoing: Bool, context: MessageDisplayContext) -> MessageDeliveryState {
        guard isOutgoing, let readUpTo = context.readUpTo, message.messageId <= readUpTo else { return .delivered }
        return .read
    }

    /// Действия с доставленным сообщением: редактировать можно своё текстовое сообщение, «Кем прочитано» — любое
    /// сообщение групповой переписки. Режим редактирования здесь не учитывается — действия в это время скрывает
    /// экран (`ChatViewModel.areMessageActionsEnabled`): включение и выключение режима не пересобирают ленту.
    /// - Parameters:
    ///   - message: сообщение с сервера.
    ///   - context: общие параметры отображения.
    static func actions(for message: Message, context: MessageDisplayContext) -> [MessageAction] {
        var actions: [MessageAction] = []
        if message.senderId == context.currentUserId, message.type == .text {
            actions.append(.edit)
        }
        if context.conversationType == .group {
            actions.append(.readers)
        }
        return actions
    }

    /// Собирает для отображения сообщение, ещё не подтверждённое сервером. Оно всегда исходящее и без времени:
    /// момент нажатия «Отправить» — ещё не время сообщения на сервере, вместо него показывается состояние доставки.
    /// Неотправленное можно повторить или удалить; у отправляющегося действий нет, а редактировать можно только
    /// доставленное сообщение.
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
            time: nil,
            editedLabel: nil,
            deliveryState: deliveryState,
            deliveryStateLabel: deliveryState == .failed ? context.strings.failed : context.strings.sending,
            actions: deliveryState == .failed ? [.retrySending, .deleteUnsent] : []
        )
    }

    /// Форматирует время отправки для пузыря: только время, без даты (см. `MessageTimeFormatter`).
    /// - Parameters:
    ///   - date: время отправки.
    ///   - context: язык и календарь.
    static func formattedTime(_ date: Date, context: MessageDisplayContext) -> String {
        MessageTimeFormatter.timeString(from: date, locale: context.locale, calendar: context.calendar)
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
