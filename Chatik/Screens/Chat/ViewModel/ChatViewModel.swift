//
//  ChatViewModel.swift
//  Chatik
//

import Foundation
import os

/// Состояние экрана переписки: сообщения с бесшовной подгрузкой более старых, ввод и отправка сообщения.
///
/// Сообщения хранит `PaginatedList` в порядке выдачи сервера — сначала самые новые; продолжение выдачи идёт
/// по курсору `nextBlockId`. Каждая полученная страница и каждое отправленное сообщение сохраняются в локальную БД,
/// и при открытии экрана до ответа сервера (или вместо него, если сети нет) показываются сообщения из БД.
///
/// Тексты и DisplayModel собираются в `ChatViewModel+Texts`.
@MainActor
@Observable
final class ChatViewModel {
    /// Текст в поле ввода.
    var messageText = ""
    /// `true`, пока выполняется запрос отправки.
    private(set) var isSending = false
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Сколько последних сообщений читается из БД при открытии экрана.
    static let cachedMessagesLimit = 200

    let conversation: Conversation
    let list = PaginatedList<Message>(prefetchThreshold: 10)
    /// Отправленные с этого экрана сообщения, сначала самые новые. Показываются, пока они новее всех сообщений
    /// `list`: загрузка первой страницы, ответ на которую сервер собрал до отправки, иначе заменила бы список без них.
    private(set) var sentMessages: [Message] = []
    let sessionService: SessionServiceProtocol
    let userCache: UserCacheServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let messageTextValidator: MessageTextValidatorProtocol
    let now: () -> Date
    private let messageService: MessageServiceProtocol
    private let messageStorage: MessageStorageServiceProtocol

    /// - Parameters:
    ///   - conversation: открытая переписка.
    ///   - messageService: сервис сообщений — источник `/messages/*`.
    ///   - messageStorage: хранилище сообщений в БД.
    ///   - sessionService: сессия — по ней сообщения делятся на исходящие и входящие.
    ///   - userCache: кэш пользователей — имена собеседника и отправителей.
    ///   - localizationService: язык форматирования времени.
    ///   - messageTextValidator: проверка текста перед отправкой.
    ///   - now: текущее время; подменяется в тестах форматирования.
    init(
        conversation: Conversation,
        messageService: MessageServiceProtocol,
        messageStorage: MessageStorageServiceProtocol,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        messageTextValidator: MessageTextValidatorProtocol,
        now: @escaping () -> Date = { Date() }
    ) {
        self.conversation = conversation
        self.messageService = messageService
        self.messageStorage = messageStorage
        self.sessionService = sessionService
        self.userCache = userCache
        self.localizationService = localizationService
        self.messageTextValidator = messageTextValidator
        self.now = now
    }

    // MARK: - Список

    /// Загружает самые новые сообщения заново: при открытии экрана и pull-to-refresh внизу ленты. Если список пуст
    /// (открытие экрана), до ответа сервера показываются сообщения из локальной БД; при ошибке сети они остаются
    /// на экране. При обновлении лента заменяется первой страницей — более старые сообщения подгрузятся снова при прокрутке.
    ///
    /// Загрузка идёт в отдельной задаче: SwiftUI отменяет задачи `.task` и `.refreshable` (при уходе с экрана,
    /// при перерисовке во время обновления), и запрос оборвался бы, показав ошибку вместо новых сообщений.
    func loadFirstPage() async {
        let task = Task { await list.refresh(cached: loadCachedMessages, load: loadPage) }
        show(await task.value)
    }

    /// Начинает загрузку более старых сообщений, если показано одно из самых старых.
    /// - Parameter message: сообщение, которое появилось на экране.
    func prefetchNextPageIfNeeded(currentMessage message: MessageDisplayModel) {
        guard let item = list.items.first(where: { $0.id == message.id }) else { return }
        list.prefetchNextPageIfNeeded(currentItem: item, load: loadPage, onOutcome: show)
    }

    /// Запрашивает страницу сообщений и сохраняет её в локальную БД.
    /// - Parameter context: курсор — блок, с которого продолжить; `nil` — с самого нового блока.
    private func loadPage(_ context: PaginationContext) async throws -> PaginatedListPage<Message> {
        let page = try await messageService.fetchMessages(conversationId: conversation.conversationId, blockId: context.cursor)
        await save(page.messages)
        loadSenders(of: page.messages)
        return PaginatedListPage(items: page.messages, hasNext: page.hasNext && page.nextBlockId != nil, nextCursor: page.nextBlockId)
    }

    /// Показывает сообщение, если загрузка страницы не удалась. Устаревшие ответы игнорируются.
    /// - Parameter outcome: итог загрузки страницы.
    private func show(_ outcome: PaginationOutcome) {
        guard case .failed(let error) = outcome else { return }
        errorMessage = ErrorMessages.message(for: error)
    }

    // MARK: - Отправка

    /// Обработчик кнопки отправки: отправляет сообщение, если текст допустим и отправка ещё не идёт.
    /// Флаг отправки поднимается до старта задачи: иначе второй тап, пришедший до её запуска, отправил бы дубликат.
    func didTapSend() {
        guard isSendEnabled else { return }
        isSending = true
        Task { await send() }
    }

    /// Отправляет текст из поля ввода. При успехе сообщение появляется в списке, сохраняется в БД, поле очищается;
    /// при ошибке показывается сообщение, а текст остаётся в поле — его можно отправить ещё раз.
    func send() async {
        isSending = true
        defer { isSending = false }

        do {
            let text = messageText
            let message = try await messageService.send(conversationId: conversation.conversationId, text: text)
            sentMessages.insert(message, at: 0)
            messageText = ""
            await save([message])
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    // MARK: - Локальная БД

    /// Читает последние сообщения переписки из БД для показа до ответа сервера. Ошибка чтения не показывается
    /// пользователю — список просто дождётся сервера.
    /// - Returns: сообщения, сначала самые новые; пустой массив, если БД пуста или не прочиталась.
    private func loadCachedMessages() async -> [Message] {
        do {
            let messages = try await messageStorage.fetchLatest(
                conversationId: conversation.conversationId,
                limit: Self.cachedMessagesLimit
            )
            loadSenders(of: messages)
            return messages
        } catch {
            Logger.storage.error("Не удалось прочитать сообщения из БД: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Сохраняет сообщения в БД. Ошибка записи не мешает показать их на экране.
    /// - Parameter messages: сообщения из ответа сервера.
    private func save(_ messages: [Message]) async {
        do {
            try await messageStorage.save(messages: messages)
        } catch {
            Logger.storage.error("Не удалось сохранить сообщения в БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Запускает загрузку отправителей, если их имена показываются (групповая переписка). Список не ждёт
    /// загрузки — пока отправителя нет, вместо имени показывается заглушка.
    /// - Parameter messages: сообщения, отправители которых нужны.
    private func loadSenders(of messages: [Message]) {
        guard conversation.type == .group, !messages.isEmpty else { return }
        let senderIds = Array(Set(messages.map(\.senderId))).sorted()
        Task { await userCache.loadUsers(ids: senderIds) }
    }
}
