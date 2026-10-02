//
//  ChatViewModel+Texts.swift
//  Chatik
//

import Foundation

/// Производные данные экрана переписки: заголовок, сообщения для отображения, состояние ввода.
extension ChatViewModel {
    /// Сообщения для отображения, сначала самые новые. Аватар и имя отправителя есть только у первого сообщения
    /// серии подряд от одного отправителя. Отправители читаются из кэша пользователей — Observation отслеживает
    /// это чтение, и сообщения перерисуются, когда пользователи загрузятся.
    var messages: [MessageDisplayModel] {
        let context = MessageDisplayContext(
            currentUserId: sessionService.currentUser?.userId,
            locale: localizationService.language.locale,
            calendar: .current,
            now: now()
        )
        let items = displayedMessages
        return items.indices.map { index in
            let message = items[index]
            // Порядок — от новых к старым, поэтому первое сообщение серии — то, за которым идёт сообщение
            // другого отправителя или конец загруженной ленты.
            let isFirstInSeries = index + 1 == items.count || items[index + 1].senderId != message.senderId
            let sender = isFirstInSeries ? cachedSender(id: message.senderId) : nil
            return MessageDisplayModel(message: message, sender: sender, context: context)
        }
    }

    /// Отправитель по идентификатору: текущий пользователь — из сессии (там актуальный профиль),
    /// остальные — из кэша пользователей.
    /// - Parameter id: идентификатор отправителя.
    private func cachedSender(id: Int) -> CachedUser {
        guard let currentUser = sessionService.currentUser, currentUser.userId == id else { return userCache.user(id: id) }
        return .loaded(currentUser)
    }

    /// Сообщения списка с наложенными `liveMessages`, сначала самые новые. Версия из `liveMessages` заменяет
    /// сообщение списка, если она не старше. Сообщения, которых в списке нет, встают в начало, если они новее всех
    /// сообщений списка; более старые лежат за пределами загруженных страниц и подгрузятся на своё место
    /// при прокрутке, а не встанут в ленту под видом самых новых.
    private var displayedMessages: [Message] {
        let listedIds = Set(list.items.map(\.id))
        let newestListedId = list.items.first?.id
        let fresh = liveMessages.values
            .filter { message in
                guard !listedIds.contains(message.id) else { return false }
                guard let newestListedId else { return true }
                return message.id > newestListedId
            }
            .sorted { $0.id > $1.id }
        let listed = list.items.map { message in
            guard let live = liveMessages[message.id], live.isNotOlder(than: message) else { return message }
            return live
        }
        return fresh + listed
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

    /// `true`, пока грузятся самые новые сообщения (открытие экрана).
    var isLoadingFirstPage: Bool {
        list.isLoadingFirstPage
    }

    /// `true`, пока грузятся более старые сообщения.
    var isLoadingNextPage: Bool {
        list.isLoadingNextPage
    }

    /// `true`, если показывать нечего: сообщений нет и первая страница не грузится.
    var isEmpty: Bool {
        list.isEmpty && liveMessages.isEmpty
    }

    /// Можно ли нажать «Отправить»: отправка не идёт и текст проходит проверку.
    var isSendEnabled: Bool {
        guard !isSending else { return false }
        return messageTextValidator.validate(messageText) == nil
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
