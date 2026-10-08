//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation
import os

/// Состояние экрана списка чатов: постраничный список переписок, переход в профиль, создание личного
/// диалога. Подписан на выход из аккаунта (`AuthServiceObserver`): перед выходом отменяет загрузки списка.
///
/// Список переписок хранит `PaginatedList`: он же отбрасывает устаревшие ответы, не допускает дубликатов
/// и считает сдвиг для следующей страницы. ViewModel остаётся владельцем запроса и текстов ошибок.
///
/// Список хранит переписки, а не строки: собеседник берётся из кэша пользователей при каждом чтении
/// `conversations`, поэтому строка обновляется сама, когда собеседник догрузится.
///
/// Переписки из событий WebSocket хранятся отдельно от `PaginatedList` (`liveConversations`) и накладываются
/// на него при отображении: обновление списка, ответ на которое сервер собрал раньше события, иначе стёрло бы их.
@MainActor
@Observable
final class ChatListViewModel: AuthServiceObserver {
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Размер страницы списка переписок.
    static let pageSize = 30

    private let list = PaginatedList<Conversation>()
    /// Переписки, пришедшие событиями WebSocket, по `conversationId` — последняя известная версия каждой.
    private var liveConversations: [Int: Conversation] = [:]
    /// Идущие загрузки и сверки первой страницы — хранятся, чтобы отменить их и дождаться при выходе. Обычно одна;
    /// несколько — пока заменённая загрузка (pull-to-refresh поверх открытия) ещё не завершилась после отмены
    /// или поверх загрузки идёт сверка после подключения к WebSocket.
    private var firstPageTasks: Set<Task<PaginationOutcome, Never>> = []
    /// Последнее начатое сохранение созданной переписки; следующие сохранения выстраиваются за ним.
    private var createdConversationSaveTask: Task<Void, Never>?
    private let sessionService: SessionServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let conversationStorage: ConversationStorageServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let realtimeService: RealtimeServiceProtocol
    private let router: ChatListRouter

    init(
        authService: AuthServiceProtocol,
        sessionService: SessionServiceProtocol,
        conversationService: ConversationServiceProtocol,
        conversationStorage: ConversationStorageServiceProtocol,
        userCache: UserCacheServiceProtocol,
        realtimeService: RealtimeServiceProtocol,
        router: ChatListRouter
    ) {
        self.sessionService = sessionService
        self.conversationService = conversationService
        self.conversationStorage = conversationStorage
        self.userCache = userCache
        self.realtimeService = realtimeService
        self.router = router
        authService.addObserver(self)
    }

    /// Переписки текущего пользователя, сначала самые новые. Собеседники читаются из кэша пользователей —
    /// Observation отслеживает это чтение, и строки перерисуются, когда собеседники загрузятся.
    var conversations: [ChatRowDisplayModel] {
        displayedConversations.map { conversation in
            ChatRowDisplayModel(conversation: conversation, opponent: conversation.opponentUserId.map(userCache.user(id:)))
        }
    }

    /// Переписки списка с наложенными событиями WebSocket: версия из события заменяет переписку списка, если она
    /// не старше; новые переписки, которых нет в списке, встают в начало, если они новее всех переписок списка.
    /// Более старые лежат за пределами загруженных страниц и придут на своё место при прокрутке.
    private var displayedConversations: [Conversation] {
        let listedIds = Set(list.items.map(\.id))
        let newestListedId = listedIds.max()
        let fresh = liveConversations.values
            .filter { conversation in
                guard !listedIds.contains(conversation.id) else { return false }
                guard let newestListedId else { return true }
                return conversation.id > newestListedId
            }
            .sorted { $0.id > $1.id }
        let listed = list.items.map { conversation in
            guard let live = liveConversations[conversation.id], live.isNotOlder(than: conversation) else { return conversation }
            return live
        }
        return fresh + listed
    }

    /// `true`, пока грузится первая страница (при открытии экрана и pull-to-refresh).
    var isLoadingFirstPage: Bool {
        list.isLoadingFirstPage
    }

    /// `true`, пока грузится следующая страница.
    var isLoadingNextPage: Bool {
        list.isLoadingNextPage
    }

    /// `true`, если показывать нечего: список пуст, первая страница не грузится и событий о новых переписках не было.
    var isEmpty: Bool {
        list.isEmpty && liveConversations.isEmpty
    }

    /// Идентификатор переписки, открытой поверх списка: её строка подсвечена, пока экран переписки показан.
    /// `nil` — ни одна переписка не открыта.
    var selectedConversationId: Int? {
        router.openedConversationId
    }

    /// URL аватара текущего пользователя для кнопки профиля: уменьшенная копия, если она есть.
    /// `nil` — аватар не установлен, кнопка показывает изображение по умолчанию.
    var avatarURL: URL? {
        guard let avatar = sessionService.currentUser?.avatar else { return nil }
        return avatar.smallURL ?? avatar.url
    }

    // MARK: - Список

    /// Загружает список переписок заново с первой страницы: при открытии экрана и pull-to-refresh.
    /// Если список пуст (открытие экрана), до ответа сервера показываются переписки из локальной БД.
    /// Загрузка идёт в отдельной задаче, чтобы выход мог её отменить. Отмена вызывающей задачи (SwiftUI отменяет
    /// `.task` при уходе экрана) её не прерывает: ViewModel живёт дольше экрана, и загруженная страница пригодится.
    /// Прежняя загрузка отменяется: её ответ всё равно был бы отброшен, а в БД писать его незачем.
    func loadFirstPage() async {
        firstPageTasks.forEach { $0.cancel() }
        let task = Task { await list.refresh(cached: loadCachedConversations, load: loadPage) }
        firstPageTasks.insert(task)
        let outcome = await task.value
        firstPageTasks.remove(task)
        show(outcome)
    }

    /// Сверяет начало списка с сервером, не сбрасывая подгруженные дальше страницы. Идущую загрузку первой
    /// страницы (открытие экрана) не отменяет — её ответ не пропадает зря. Задача хранится вместе с загрузками
    /// первой страницы, чтобы выход мог её отменить и дождаться.
    func syncFirstPage() async {
        let task = Task { await list.syncFirstPage(load: loadPage) }
        firstPageTasks.insert(task)
        let outcome = await task.value
        firstPageTasks.remove(task)
        show(outcome)
    }

    /// Начинает загрузку следующей страницы, если показана одна из последних переписок списка.
    /// - Parameter conversation: переписка, которая появилась на экране.
    func prefetchNextPageIfNeeded(currentConversation conversation: ChatRowDisplayModel) {
        guard let item = list.items.first(where: { $0.id == conversation.id }) else { return }
        list.prefetchNextPageIfNeeded(currentItem: item, load: loadPage, onOutcome: show)
    }

    /// Добавляет только что созданную переписку в начало списка и открывает её. Если она в списке уже есть —
    /// не дублирует: повторный `createSingle` с тем же собеседником возвращает уже существующую переписку.
    /// - Parameter conversation: переписка, с которой завершился экран создания.
    func didCreateConversation(_ conversation: Conversation) {
        list.insertIfAbsent(conversation)
        router.showConversation(conversation)
        let previousSave = createdConversationSaveTask
        createdConversationSaveTask = Task {
            await previousSave?.value
            await saveCreatedConversation(conversation)
        }
    }

    /// Запрашивает страницу переписок и сохраняет её в локальную БД. Собеседников кэш пользователей
    /// дозагружает сам — по action `users` из того же ответа.
    /// - Parameter context: сколько переписок уже получено — от этого числа идёт сдвиг выдачи.
    private func loadPage(_ context: PaginationContext) async throws -> PaginatedListPage<Conversation> {
        let page = try await conversationService.fetchConversations(
            offset: context.isFirstPage ? nil : context.loadedCount,
            count: Self.pageSize
        )
        // Загрузку отменили (выход из аккаунта), пока шёл запрос: страницу нельзя писать в БД —
        // она может попасть туда уже после очистки.
        try Task.checkCancellation()
        await savePage(page, isFirstPage: context.isFirstPage)
        return PaginatedListPage(items: page.conversations, hasNext: page.hasNext)
    }

    // MARK: - Локальная БД

    /// Читает переписки из локальной БД для показа до ответа сервера и запускает загрузку их собеседников:
    /// у ответа БД нет action `users`. Список не ждёт собеседников — пока их нет, строки показывают заглушку.
    /// Ошибка чтения не показывается пользователю — список просто дождётся сервера.
    /// - Returns: переписки; пустой массив, если БД пуста или не прочиталась.
    private func loadCachedConversations() async -> [Conversation] {
        do {
            let conversations = try await conversationStorage.fetchLatest(limit: Self.pageSize)
            let opponentIds = conversations.compactMap(\.opponentUserId)
            Task { await userCache.loadUsers(ids: opponentIds) }
            return conversations
        } catch {
            Logger.storage.error("Не удалось прочитать переписки из БД: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Сохраняет страницу переписок из ответа сервера. Ошибка записи не мешает показать страницу.
    /// - Parameters:
    ///   - page: страница из ответа сервера.
    ///   - isFirstPage: `true` — страница первая; из БД удаляются переписки, которых больше нет на сервере.
    private func savePage(_ page: ConversationsPage, isFirstPage: Bool) async {
        do {
            try await conversationStorage.save(page: page, isFirstPage: isFirstPage)
        } catch {
            Logger.storage.error("Не удалось сохранить страницу переписок в БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Сохраняет только что созданную переписку, чтобы она была в списке и без сети.
    /// - Parameter conversation: переписка, с которой завершился экран создания.
    private func saveCreatedConversation(_ conversation: Conversation) async {
        do {
            try await conversationStorage.save(conversation: conversation)
        } catch {
            Logger.storage.error("Не удалось сохранить созданную переписку в БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Показывает сообщение, если загрузка страницы не удалась. Устаревшие ответы игнорируются.
    /// - Parameter outcome: итог загрузки страницы.
    private func show(_ outcome: PaginationOutcome) {
        guard case .failed(let error) = outcome else { return }
        errorMessage = ErrorMessages.message(for: error)
    }

    // MARK: - События WebSocket

    /// Применяет события реального времени, пока задачу не отменят. После (пере)подключения начало списка
    /// сверяется через REST: события, пришедшие без соединения, потеряны.
    func observeRealtimeEvents() async {
        for await event in realtimeService.events() {
            handle(event)
        }
    }

    /// Применяет одно событие реального времени. Переписка уже сохранена в БД сервисом WebSocket.
    /// - Parameter event: событие.
    func handle(_ event: RealtimeEvent) {
        switch event {
        case .connected:
            Task { await syncFirstPage() }
        case let .conversationCreated(conversation):
            guard liveConversations[conversation.id].map(conversation.isNotOlder(than:)) ?? true else { return }
            liveConversations[conversation.id] = conversation
        case .messageReceived, .messageEdited:
            break
        }
    }

    // MARK: - Навигация

    /// Обработчик кнопки-аватара: открывает экран профиля.
    func didTapProfile() {
        router.showProfile()
    }

    /// Обработчик тапа по строке списка: открывает переписку.
    /// - Parameter row: строка, по которой тапнули.
    func didSelectConversation(_ row: ChatRowDisplayModel) {
        guard let conversation = displayedConversations.first(where: { $0.id == row.id }) else { return }
        router.showConversation(conversation)
    }

    /// Обработчик пункта «Личный диалог» меню создания: открывает экран создания личного диалога.
    func didTapCreateSingleConversation() {
        router.showCreateSingleConversation()
    }

    // MARK: - Выход

    /// Выход из аккаунта начинается (`AuthServiceObserver`): загрузки списка отменяются, выход дожидается их
    /// и записей в БД. Иначе страница, пришедшая во время выхода, записалась бы в БД уже после её очистки
    /// и досталась следующему пользователю.
    func authServiceWillLogout() async {
        let firstPageTasks = firstPageTasks
        firstPageTasks.forEach { $0.cancel() }
        await list.cancelLoading()
        for task in firstPageTasks {
            _ = await task.value
        }
        await createdConversationSaveTask?.value
    }
}
