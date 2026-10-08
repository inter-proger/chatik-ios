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
/// Сообщения, полученные помимо страниц, — отправленные с экрана и пришедшие событиями WebSocket — хранятся
/// отдельно (`liveMessages`) и накладываются на список при отображении: из двух версий одного сообщения
/// показывается версия с большим `updatedAt`.
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
    /// Сообщения, полученные помимо страниц (отправленные с экрана, пришедшие событиями WebSocket), по `messageId` —
    /// последняя известная версия каждого. Хранятся отдельно от `list`: обновление первой страницы, ответ на которую
    /// сервер собрал раньше, иначе заменило бы список без них или откатило бы правку.
    private(set) var liveMessages: [Int: Message] = [:]
    let sessionService: SessionServiceProtocol
    let userCache: UserCacheServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let messageTextValidator: MessageTextValidatorProtocol
    let now: () -> Date
    private let messageService: MessageServiceProtocol
    private let messageStorage: MessageStorageServiceProtocol
    private let realtimeService: RealtimeServiceProtocol

    /// - Parameters:
    ///   - conversation: открытая переписка.
    ///   - messageService: сервис сообщений — источник `/messages/*`.
    ///   - messageStorage: хранилище сообщений в БД.
    ///   - sessionService: сессия — по ней сообщения делятся на исходящие и входящие.
    ///   - userCache: кэш пользователей — имена собеседника и отправителей.
    ///   - localizationService: язык форматирования времени.
    ///   - messageTextValidator: проверка текста перед отправкой.
    ///   - realtimeService: события WebSocket — новые и отредактированные сообщения.
    ///   - now: текущее время; подменяется в тестах форматирования.
    init(
        conversation: Conversation,
        messageService: MessageServiceProtocol,
        messageStorage: MessageStorageServiceProtocol,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        messageTextValidator: MessageTextValidatorProtocol,
        realtimeService: RealtimeServiceProtocol,
        now: @escaping () -> Date = { Date() }
    ) {
        self.conversation = conversation
        self.messageService = messageService
        self.messageStorage = messageStorage
        self.sessionService = sessionService
        self.userCache = userCache
        self.localizationService = localizationService
        self.messageTextValidator = messageTextValidator
        self.realtimeService = realtimeService
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

    /// Сверяет самые новые сообщения с сервером, не сбрасывая подгруженную историю: лента прокручена назад —
    /// загруженные страницы и позиция остаются на месте. Идущая загрузка первой страницы не прерывается.
    func syncFirstPage() async {
        let task = Task { await list.syncFirstPage(load: loadPage) }
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

    /// Отправляет текст из поля ввода. При успехе сообщение появляется в списке, сохраняется в БД, а из поля
    /// убирается отправленный текст; при ошибке показывается сообщение, а текст остаётся в поле — его можно
    /// отправить ещё раз. Поле во время отправки не блокируется (иначе оно теряет фокус и клавиатура опускается),
    /// поэтому набранное за время запроса после отправленного текста сохраняется в поле.
    func send() async {
        isSending = true
        defer { isSending = false }

        do {
            let text = messageText
            let message = try await messageService.send(conversationId: conversation.conversationId, text: text)
            applyLive(message)
            removeSentText(text)
            await save([message])
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Убирает из поля отправленный текст, оставляя дописанное после него за время запроса. Если начало поля
    /// за это время изменили, поле не трогается: что из него уже отправлено, понять нельзя.
    /// - Parameter text: текст, ушедший на сервер.
    private func removeSentText(_ text: String) {
        guard messageText.hasPrefix(text) else { return }
        messageText.removeFirst(text.count)
    }

    // MARK: - События WebSocket

    /// Применяет события реального времени, пока задачу не отменят. После (пере)подключения самые новые
    /// сообщения сверяются через REST: события, пришедшие без соединения, потеряны.
    func observeRealtimeEvents() async {
        for await event in realtimeService.events() {
            handle(event)
        }
    }

    /// Применяет одно событие реального времени. Сообщения уже сохранены в БД сервисом WebSocket; сообщения
    /// других переписок пропускаются.
    /// - Parameter event: событие.
    func handle(_ event: RealtimeEvent) {
        switch event {
        case .connected:
            Task { await syncFirstPage() }
        case let .messageReceived(message), let .messageEdited(message):
            guard message.conversationId == conversation.conversationId else { return }
            applyLive(message)
        case .conversationCreated:
            break
        }
    }

    /// Запоминает версию сообщения, полученную помимо страниц, если она не старше уже известной. Повторное
    /// применение той же версии (событие о собственном отправленном сообщении) ничего не меняет.
    /// - Parameter message: сообщение из ответа `/messages/send` или события WebSocket.
    private func applyLive(_ message: Message) {
        guard liveMessages[message.id].map(message.isNotOlder(than:)) ?? true else { return }
        liveMessages[message.id] = message
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

    /// Запускает загрузку отправителей — для их имён и аватаров. Текущий пользователь не запрашивается: он берётся
    /// из сессии. Список не ждёт загрузки — пока отправителя нет, вместо имени показывается заглушка.
    /// - Parameter messages: сообщения, отправители которых нужны.
    private func loadSenders(of messages: [Message]) {
        let currentUserId = sessionService.currentUser?.userId
        let senderIds = Set(messages.map(\.senderId)).filter { $0 != currentUserId }.sorted()
        guard !senderIds.isEmpty else { return }
        Task { await userCache.loadUsers(ids: senderIds) }
    }
}
