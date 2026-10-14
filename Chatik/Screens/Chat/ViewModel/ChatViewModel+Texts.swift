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
        messages.isEmpty && (isSyncing || !isLoaded)
    }

    /// `true`, если показывать нечего: кэш прочитан, сообщений нет и синхронизация не идёт.
    var isEmpty: Bool {
        messages.isEmpty && !isSyncing && isLoaded
    }

    /// Можно ли нажать «Отправить»: текст проходит проверку. Идущая отправка не мешает — сообщения встают в очередь.
    var isSendEnabled: Bool {
        messageTextValidator.validate(messageText) == nil
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
