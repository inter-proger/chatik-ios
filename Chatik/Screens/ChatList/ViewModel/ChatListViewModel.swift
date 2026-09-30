//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана списка чатов: постраничный список переписок, переход в профиль, создание личного
/// диалога и выход из аккаунта.
@MainActor
@Observable
final class ChatListViewModel {
    /// Переписки текущего пользователя, сначала самые новые.
    private(set) var conversations: [ChatRowDisplayModel] = []
    /// `true`, пока грузится первая страница (при открытии экрана и pull-to-refresh).
    private(set) var isLoadingFirstPage = false
    /// `true`, пока грузится следующая страница.
    private(set) var isLoadingNextPage = false
    /// `true`, пока выполняется запрос выхода.
    private(set) var isLoggingOut = false
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Размер страницы списка переписок.
    static let pageSize = 30
    /// За сколько переписок до конца списка начинает грузиться следующая страница.
    private let prefetchThreshold = 5
    private var hasMorePages = true
    /// Сколько переписок получено с сервера — от этого числа отсчитывается следующая страница.
    /// Считается отдельно от `conversations.count`: созданная на экране переписка добавляется в список
    /// локально и позицию в серверной выдаче не сдвигает.
    private var loadedCount = 0
    /// Номер актуальной загрузки списка. Растёт при каждой загрузке первой страницы: ответы,
    /// пришедшие для прежнего номера (устаревшая загрузка), отбрасываются.
    private var listGeneration = 0
    private var nextPageTask: Task<Void, Never>?

    private let authService: AuthServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let router: ChatListRouter

    init(
        authService: AuthServiceProtocol,
        sessionService: SessionServiceProtocol,
        conversationService: ConversationServiceProtocol,
        router: ChatListRouter
    ) {
        self.authService = authService
        self.sessionService = sessionService
        self.conversationService = conversationService
        self.router = router
    }

    /// URL аватара текущего пользователя для кнопки профиля: уменьшенная копия, если она есть.
    /// `nil` — аватар не установлен, кнопка показывает изображение по умолчанию.
    var avatarURL: URL? {
        guard let avatar = sessionService.currentUser?.avatar else { return nil }
        return avatar.smallURL ?? avatar.url
    }

    /// `true`, если загружать нечего: список пуст и первая страница не грузится.
    var isEmpty: Bool {
        conversations.isEmpty && !isLoadingFirstPage
    }

    // MARK: - Список

    /// Загружает список переписок заново с первой страницы: при открытии экрана и pull-to-refresh.
    /// Прежний список остаётся на экране до ответа. Начатая подгрузка следующей страницы отменяется,
    /// а её опоздавший ответ отбрасывается — иначе она дописалась бы к уже обновлённому списку.
    func loadFirstPage() async {
        nextPageTask?.cancel()
        isLoadingNextPage = false
        listGeneration += 1
        let generation = listGeneration
        isLoadingFirstPage = true
        // Флаг снимает только актуальная загрузка: если за время запроса началась новая, флаг принадлежит ей.
        defer { if generation == listGeneration { isLoadingFirstPage = false } }

        do {
            let page = try await conversationService.fetchConversations(offset: nil, count: Self.pageSize)
            guard generation == listGeneration else { return }
            conversations = []
            loadedCount = 0
            apply(page)
        } catch {
            guard generation == listGeneration else { return }
            // Список остаётся прежним, но пагинация к нему больше не относится: следующая страница ушла бы
            // со сдвигом от неактуальной выдачи.
            hasMorePages = false
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Начинает загрузку следующей страницы, если показана одна из последних переписок списка.
    /// - Parameter conversation: переписка, которая появилась на экране.
    func prefetchNextPageIfNeeded(currentConversation conversation: ChatRowDisplayModel) {
        guard hasMorePages, !isLoadingFirstPage, !isLoadingNextPage else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        guard index >= conversations.count - prefetchThreshold else { return }
        isLoadingNextPage = true
        nextPageTask = Task { await loadNextPage() }
    }

    /// Загружает следующую страницу и дописывает её к списку.
    /// Флаг загрузки поднимает вызывающий (`prefetchNextPageIfNeeded`) — до старта задачи,
    /// чтобы повторные появления строк на экране не запускали вторую загрузку.
    func loadNextPage() async {
        let generation = listGeneration
        defer { if generation == listGeneration { isLoadingNextPage = false } }

        do {
            let page = try await conversationService.fetchConversations(offset: loadedCount, count: Self.pageSize)
            guard generation == listGeneration else { return }
            apply(page)
        } catch {
            guard generation == listGeneration else { return }
            // Повторять на каждом появлении строки не нужно: иначе при недоступном сервере скролл
            // превратится в поток запросов и сообщений. Следующая попытка — по pull-to-refresh.
            hasMorePages = false
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Добавляет только что созданную переписку в начало списка. Если она там уже есть — не дублирует:
    /// повторный `createSingle` с тем же собеседником возвращает уже существующую переписку.
    /// - Parameter conversation: переписка, с которой завершился экран создания.
    func didCreateConversation(_ conversation: Conversation) {
        guard !conversations.contains(where: { $0.id == conversation.id }) else { return }
        conversations.insert(ChatRowDisplayModel(conversation: conversation), at: 0)
    }

    /// Дописывает страницу к списку, пропуская переписки, которые в нём уже есть: при постраничной выдаче
    /// со сдвигом список на сервере мог измениться между запросами, а созданная переписка уже добавлена локально.
    /// - Parameter page: ответ сервера.
    private func apply(_ page: ConversationsPage) {
        let listedIds = Set(conversations.map(\.id))
        conversations += page.conversations
            .filter { !listedIds.contains($0.id) }
            .map(ChatRowDisplayModel.init)
        loadedCount += page.conversations.count
        hasMorePages = page.hasNext
    }

    /// Обработчик кнопки-аватара: открывает экран профиля.
    func didTapProfile() {
        router.showProfile()
    }

    /// Обработчик пункта «Личный диалог» меню создания: открывает экран создания личного диалога.
    func didTapCreateSingleConversation() {
        router.showCreateSingleConversation()
    }

    /// Обработчик кнопки «Выйти»: запускает выход, если он ещё не выполняется.
    func didTapLogout() {
        guard !isLoggingOut else { return }
        Task { await logout() }
    }

    /// Завершает сессию на сервере и локально; приложение переключится на экран авторизации.
    /// Если сервер ответил «не авторизован», сессии уже нет — завершаем локально без сообщения об ошибке.
    /// При прочих ошибках показывает сообщение и остаётся на экране.
    func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        do {
            try await authService.logout()
            await sessionService.end()
        } catch NetworkError.api(let code) where code == NetworkError.Code.unauthorized {
            await sessionService.end()
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }
}
