//
//  CreateSingleConversationViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана создания личного диалога: постраничный список пользователей с поиском,
/// выбор собеседника и создание переписки с ним.
@MainActor
@Observable
final class CreateSingleConversationViewModel {
    /// Пользователи для выбора собеседника; текущий пользователь в список не попадает.
    private(set) var users: [UserRowDisplayModel] = []
    /// Выбранный собеседник. `nil` — никто не выбран, кнопка «Создать» неактивна.
    private(set) var selectedUserId: Int?
    /// `true`, пока грузится первая страница (при открытии, поиске или pull-to-refresh).
    private(set) var isLoadingFirstPage = false
    /// `true`, пока грузится следующая страница.
    private(set) var isLoadingNextPage = false
    /// `true`, пока выполняется запрос создания переписки.
    private(set) var isCreating = false
    /// Содержимое поля поиска.
    var searchText = ""
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Размер страницы списка пользователей.
    static let pageSize = 30
    /// За сколько пользователей до конца списка начинает грузиться следующая страница.
    private let prefetchThreshold = 5
    /// Пауза после ввода в поле поиска, прежде чем уйдёт запрос.
    private let searchDebounce: Duration

    /// `maxId` для запроса следующей страницы.
    private var nextMaxId: Int?
    private var hasMorePages = true
    /// Номер актуальной загрузки списка. Растёт при каждой загрузке первой страницы: ответы,
    /// пришедшие для прежнего номера (старый поисковый запрос), отбрасываются.
    private var listGeneration = 0
    private var nextPageTask: Task<Void, Never>?

    private let usersService: UsersServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let router: CreateSingleConversationRouter

    /// - Parameters:
    ///   - usersService: сервис списка пользователей.
    ///   - conversationService: сервис переписок — для создания личного диалога.
    ///   - sessionService: сервис сессии; текущий пользователь исключается из списка.
    ///   - router: роутер экрана; через него экран завершается — отменой или созданной перепиской.
    ///   - searchDebounce: пауза после ввода в поле поиска перед запросом.
    init(
        usersService: UsersServiceProtocol,
        conversationService: ConversationServiceProtocol,
        sessionService: SessionServiceProtocol,
        router: CreateSingleConversationRouter,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.usersService = usersService
        self.conversationService = conversationService
        self.sessionService = sessionService
        self.router = router
        self.searchDebounce = searchDebounce
    }

    /// `true`, если выбран собеседник и переписка ещё не создаётся.
    var isCreateButtonEnabled: Bool {
        guard !isCreating else { return false }
        return selectedUserId != nil
    }

    /// `true`, если загружать нечего: список пуст и первая страница не грузится.
    var isEmpty: Bool {
        users.isEmpty && !isLoadingFirstPage
    }

    // MARK: - Список

    /// Загружает список под текущий поисковый запрос. Вызывается при открытии экрана и при каждом изменении запроса.
    /// Непустой запрос выдерживается паузой, чтобы не отправлять запрос на каждый символ: View отменяет
    /// предыдущий вызов при новом вводе (`task(id:)`), и запрос уходит только по последнему.
    func searchTextDidChange() async {
        if !searchText.isEmpty {
            try? await Task.sleep(for: searchDebounce)
        }
        guard !Task.isCancelled else { return }
        await loadFirstPage()
    }

    /// Загружает список заново с первой страницы (pull-to-refresh, смена поискового запроса).
    /// Прежний список остаётся на экране до ответа; выбор собеседника сохраняется, если он есть в новом списке.
    func loadFirstPage() async {
        nextPageTask?.cancel()
        isLoadingNextPage = false
        listGeneration += 1
        let generation = listGeneration
        isLoadingFirstPage = true
        // Флаг снимает только актуальная загрузка: если за время запроса началась новая, флаг принадлежит ей.
        defer { if generation == listGeneration { isLoadingFirstPage = false } }

        do {
            let page = try await usersService.fetchUsers(query: searchText, maxId: nil, count: Self.pageSize)
            guard generation == listGeneration else { return }
            users = []
            apply(page)
            keepSelectionIfListed()
        } catch {
            // Список остаётся прежним, но пагинация к нему больше не относится: следующая страница ушла бы
            // с `maxId` от прошлого запроса и дописала бы к списку результаты другого поиска.
            guard generation == listGeneration else { return }
            hasMorePages = false
            nextMaxId = nil
            show(error, generation: generation)
        }
    }

    /// Начинает загрузку следующей страницы, если показан один из последних пользователей списка.
    /// - Parameter user: пользователь, который появился на экране.
    func prefetchNextPageIfNeeded(currentUser user: UserRowDisplayModel) {
        guard hasMorePages, !isLoadingFirstPage, !isLoadingNextPage else { return }
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        guard index >= users.count - prefetchThreshold else { return }
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
            let page = try await usersService.fetchUsers(query: searchText, maxId: nextMaxId, count: Self.pageSize)
            guard generation == listGeneration else { return }
            apply(page)
        } catch {
            show(error, generation: generation)
        }
    }

    // MARK: - Выбор и создание

    /// Обработчик нажатия на пользователя: выбирает его собеседником.
    /// - Parameter user: нажатый пользователь.
    func didSelect(_ user: UserRowDisplayModel) {
        guard !isCreating else { return }
        selectedUserId = user.id
    }

    /// Обработчик кнопки «Создать»: запускает создание переписки, если оно ещё не выполняется.
    func didTapCreate() {
        guard isCreateButtonEnabled else { return }
        Task { await createConversation() }
    }

    /// Обработчик кнопки «Отмена»: закрывает экран без создания переписки.
    /// Во время создания кнопка неактивна, поэтому отмена на полпути невозможна.
    func didTapCancel() {
        guard !isCreating else { return }
        router.cancel()
    }

    /// Создаёт личную переписку с выбранным пользователем и передаёт её роутеру — экран закрывается.
    /// При ошибке показывает сообщение и остаётся на экране.
    func createConversation() async {
        guard let selectedUserId else { return }
        isCreating = true
        defer { isCreating = false }

        do {
            let conversation = try await conversationService.createSingle(userId: selectedUserId)
            router.finish(with: conversation)
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    // MARK: - Private

    /// Дописывает страницу к списку, исключив текущего пользователя, и запоминает, есть ли ещё страницы.
    /// - Parameter page: ответ сервера.
    private func apply(_ page: UsersPage) {
        let currentUserId = sessionService.currentUser?.userId
        users += page.users
            .filter { $0.userId != currentUserId }
            .map(UserRowDisplayModel.init)
        nextMaxId = page.nextMaxId
        hasMorePages = page.hasNext
    }

    /// Сбрасывает выбор, если выбранного пользователя нет в новом списке, — чтобы нельзя было создать
    /// переписку с тем, кого не видно на экране.
    private func keepSelectionIfListed() {
        guard let selectedUserId, !users.contains(where: { $0.id == selectedUserId }) else { return }
        self.selectedUserId = nil
    }

    /// Показывает ошибку загрузки, если она относится к актуальному списку и загрузка не была отменена.
    /// - Parameters:
    ///   - error: ошибка сервиса.
    ///   - generation: номер загрузки, в которой произошла ошибка.
    private func show(_ error: Error, generation: Int) {
        guard generation == listGeneration, !Task.isCancelled else { return }
        errorMessage = ErrorMessages.message(for: error)
    }
}
