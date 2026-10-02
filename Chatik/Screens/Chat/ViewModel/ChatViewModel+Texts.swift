//
//  ChatViewModel+Texts.swift
//  Chatik
//

import Foundation

/// Производные данные экрана переписки: заголовок, сообщения для отображения, состояние ввода.
extension ChatViewModel {
    /// Сообщения для отображения, сначала самые новые. Отправители и собеседник читаются из кэша пользователей —
    /// Observation отслеживает это чтение, и сообщения перерисуются, когда пользователи загрузятся.
    var messages: [MessageDisplayModel] {
        let context = MessageDisplayContext(
            currentUserId: sessionService.currentUser?.userId,
            showsSenderNames: conversation.type == .group,
            locale: localizationService.language.locale,
            calendar: .current,
            now: now()
        )
        return (sentMessagesNewerThanList + list.items).map { message in
            let sender = context.showsSenderNames ? userCache.user(id: message.senderId) : nil
            return MessageDisplayModel(message: message, sender: sender, context: context)
        }
    }

    /// Отправленные сообщения, которые новее всех сообщений списка. Более старые либо уже есть в списке, либо лежат
    /// за пределами загруженных страниц (обновление после того, как пришла страница чужих сообщений) — такие
    /// подгрузятся на своё место при прокрутке, а не встанут в ленту под видом самых новых.
    private var sentMessagesNewerThanList: [Message] {
        guard let newestListedId = list.items.first?.id else { return sentMessages }
        return sentMessages.filter { $0.id > newestListedId }
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
        list.isEmpty && sentMessages.isEmpty
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
