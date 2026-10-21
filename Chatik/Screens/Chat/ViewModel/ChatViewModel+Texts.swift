//
//  ChatViewModel+Texts.swift
//  Chatik
//

import Foundation

/// Производные данные экрана переписки: заголовок, состояние ленты и ввода.
extension ChatViewModel {
    /// Неотправленные сообщения этой переписки из общей очереди, сначала самые старые.
    var outgoingMessages: [OutgoingMessage] {
        messageSendQueue.outgoingMessages.filter { $0.conversationId == conversation.conversationId }
    }

    /// Отправитель по идентификатору: текущий пользователь — из сессии (там актуальный профиль),
    /// остальные — из кэша пользователей.
    /// - Parameter id: идентификатор отправителя.
    func cachedSender(id: Int) -> CachedUser {
        guard let currentUser = sessionService.currentUser, currentUser.userId == id else { return userCache.user(id: id) }
        return .loaded(currentUser)
    }

    /// Непрочитанные для кнопки «вниз»: сообщения после указателя прочтения. При входе переписка отмечается
    /// прочитанной, поэтому это ровно новые сообщения; прочтение на другом устройстве обнуляет его само.
    private var unreadCount: Int {
        readStates.unreadCount(conversationId: conversation.conversationId) ?? currentReadState.unreadCount
    }

    /// Счётчик над кнопкой «вниз»: до 99 — точное число, выше — «99+»; `nil` — непрочитанных нет.
    var unreadBadgeText: String? {
        UnreadCountFormatter.text(for: unreadCount)
    }

    /// Значение кнопки «вниз» для VoiceOver — непрочитанные с точным числом.
    var unreadBadgeAccessibilityValue: String? {
        UnreadCountFormatter.accessibilityLabel(for: unreadCount)
    }

    /// Заголовок экрана: название группы либо имя собеседника личной переписки.
    var title: String {
        conversation.name ?? opponentTitle
    }

    /// Заголовок по собеседнику; если собеседника нет — запасной заголовок, чтобы экран не выглядел безымянным.
    private var opponentTitle: String {
        switch opponent {
        case let .loaded(user): return user.name
        case .pending: return ChatStrings.userLoading
        case .notFound: return ChatStrings.userDeleted
        case nil: return ChatStrings.titleUntitled
        }
    }

    /// `true` — собеседник ещё не загружен: вместо заголовка показывается заглушка.
    var isTitlePlaceholder: Bool {
        conversation.name == nil && opponent == .pending
    }

    /// `true` — прелоадер по центру: показать нечего, а кэш ещё читается или идёт синхронизация.
    var isShowingLoader: Bool {
        sections.isEmpty && (isSyncing || !isLoaded)
    }

    /// `true`, если показывать нечего: кэш прочитан, сообщений нет и синхронизация не идёт.
    var isEmpty: Bool {
        sections.isEmpty && !isSyncing && isLoaded
    }

    /// Можно ли нажать «Отправить» или «Сохранить»: текст проходит проверку. Идущая отправка не мешает — сообщения
    /// встают в очередь; идущий запрос правки мешает — правка отправляется один раз. Пустая правка не проходит
    /// проверку: удаления сообщений через пустую правку нет.
    var isSendEnabled: Bool {
        messageTextValidator.validate(messageText) == nil && !isEditSubmitting
    }

    /// Идёт запрос правки этой переписки: кнопка показывает индикатор, поле ввода и крестик недоступны.
    var isEditSubmitting: Bool {
        editService.isSubmitting(conversationId: conversation.conversationId)
    }

    /// `true` — включён режим редактирования: над полем ввода плашка.
    var isEditing: Bool {
        inputMode != .compose
    }

    /// Доступны ли действия с сообщениями (меню по долгому нажатию, действия VoiceOver). В режиме редактирования
    /// скрыты у всех сообщений: чтобы отредактировать другое, текущее редактирование нужно сначала закрыть. Ленту
    /// смена режима не пересобирает — действия скрывает View.
    var areMessageActionsEnabled: Bool {
        !isEditing
    }

    /// Текст редактируемого сообщения для плашки в одну строку: переводы строк заменены пробелом.
    var editBannerText: String {
        (editedMessageText ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Значок кнопки под полем ввода: отправка или сохранение правки.
    var sendButtonIcon: String {
        isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill"
    }

    /// Подпись кнопки под полем ввода для VoiceOver.
    var sendButtonLabel: String {
        isEditing ? ChatStrings.editSave : ChatStrings.send
    }

    /// Подсказка под полем ввода. Пустой текст подсказкой не сопровождается — кнопка просто неактивна.
    var inputHint: String? {
        guard case let .tooLong(maxLength) = messageTextValidator.validate(messageText) else { return nil }
        return ChatStrings.inputTooLong(maxLength: maxLength)
    }

    /// Собеседник личной переписки из кэша; `nil` — у переписки нет собеседника.
    private var opponent: CachedUser? {
        conversation.opponentUserId.map(userCache.user(id:))
    }
}
