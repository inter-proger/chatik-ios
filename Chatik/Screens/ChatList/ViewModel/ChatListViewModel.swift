//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation
import os

/// Состояние экрана списка чатов: постраничный список переписок, переход в профиль, создание личного
/// диалога и выход из аккаунта.
///
/// Список переписок хранит `PaginatedList`: он же отбрасывает устаревшие ответы, не допускает дубликатов
/// и считает сдвиг для следующей страницы. ViewModel остаётся владельцем запроса и текстов ошибок.
///
/// Список хранит переписки, а не строки: собеседник берётся из кэша пользователей при каждом чтении
/// `conversations`, поэтому строка обновляется сама, когда собеседник догрузится.
@MainActor
@Observable
final class ChatListViewModel {
    /// `true`, пока показан попап подтверждения выхода.
    var isLogoutConfirmationPresented = false
    /// `true`, пока выполняется запрос выхода.
    private(set) var isLoggingOut = false
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Размер страницы списка переписок.
    static let pageSize = 30

    private let list = PaginatedList<Conversation>()
    /// Идущие загрузки первой страницы — хранятся, чтобы отменить их и дождаться при выходе. Обычно одна;
    /// несколько — пока заменённая загрузка (pull-to-refresh поверх открытия) ещё не завершилась после отмены.
    private var firstPageTasks: Set<Task<PaginationOutcome, Never>> = []
    /// Последнее начатое сохранение созданной переписки; следующие сохранения выстраиваются за ним.
    private var createdConversationSaveTask: Task<Void, Never>?
    private let authService: AuthServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let conversationStorage: ConversationStorageServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let router: ChatListRouter

    init(
        authService: AuthServiceProtocol,
        sessionService: SessionServiceProtocol,
        conversationService: ConversationServiceProtocol,
        conversationStorage: ConversationStorageServiceProtocol,
        userCache: UserCacheServiceProtocol,
        router: ChatListRouter
    ) {
        self.authService = authService
        self.sessionService = sessionService
        self.conversationService = conversationService
        self.conversationStorage = conversationStorage
        self.userCache = userCache
        self.router = router
    }

    /// Переписки текущего пользователя, сначала самые новые. Собеседники читаются из кэша пользователей —
    /// Observation отслеживает это чтение, и строки перерисуются, когда собеседники загрузятся.
    var conversations: [ChatRowDisplayModel] {
        list.items.map { conversation in
            ChatRowDisplayModel(conversation: conversation, opponent: conversation.opponentUserId.map(userCache.user(id:)))
        }
    }

    /// `true`, пока грузится первая страница (при открытии экрана и pull-to-refresh).
    var isLoadingFirstPage: Bool {
        list.isLoadingFirstPage
    }

    /// `true`, пока грузится следующая страница.
    var isLoadingNextPage: Bool {
        list.isLoadingNextPage
    }

    /// `true`, если загружать нечего: список пуст и первая страница не грузится.
    var isEmpty: Bool {
        list.isEmpty
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

    // MARK: - Навигация

    /// Обработчик кнопки-аватара: открывает экран профиля.
    func didTapProfile() {
        router.showProfile()
    }

    /// Обработчик тапа по строке списка: открывает переписку.
    /// - Parameter row: строка, по которой тапнули.
    func didSelectConversation(_ row: ChatRowDisplayModel) {
        guard let conversation = list.items.first(where: { $0.id == row.id }) else { return }
        router.showConversation(conversation)
    }

    /// Обработчик пункта «Личный диалог» меню создания: открывает экран создания личного диалога.
    func didTapCreateSingleConversation() {
        router.showCreateSingleConversation()
    }

    // MARK: - Выход

    /// Обработчик кнопки «Выйти»: показывает попап подтверждения, если выход ещё не выполняется.
    func didTapLogout() {
        guard !isLoggingOut else { return }
        isLogoutConfirmationPresented = true
    }

    /// Обработчик подтверждения в попапе: запускает выход. Отмена ничего не делает — попап
    /// закрывается самим `Alert` через привязку `isLogoutConfirmationPresented`.
    func didTapConfirmLogout() {
        guard !isLoggingOut else { return }
        Task { await logout() }
    }

    /// Завершает сессию на сервере и локально; приложение переключится на экран авторизации.
    /// Если сервер ответил «не авторизован», сессии уже нет — завершаем локально без сообщения об ошибке.
    /// При прочих ошибках показывает сообщение и остаётся на экране — загрузки списка не прерываются.
    func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        do {
            try await authService.logout()
            await endSession()
        } catch NetworkError.api(let code) where code == NetworkError.Code.unauthorized {
            await endSession()
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Отменяет загрузки списка, дожидается записей в БД и только затем завершает сессию: иначе страница,
    /// пришедшая во время выхода, записалась бы в БД уже после её очистки и досталась следующему пользователю.
    private func endSession() async {
        let firstPageTasks = firstPageTasks
        firstPageTasks.forEach { $0.cancel() }
        await list.cancelLoading()
        for task in firstPageTasks {
            _ = await task.value
        }
        await createdConversationSaveTask?.value
        await sessionService.end()
    }
}
