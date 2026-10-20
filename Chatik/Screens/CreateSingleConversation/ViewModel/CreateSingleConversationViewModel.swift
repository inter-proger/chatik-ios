//
//  CreateSingleConversationViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана создания личного диалога: постраничный список пользователей с поиском,
/// выбор собеседника и создание переписки с ним.
///
/// Список пользователей хранит `PaginatedList`: он же отбрасывает ответы устаревших поисковых запросов,
/// не допускает дубликатов и продолжает выдачу по курсору `maxId`.
@MainActor
@Observable
final class CreateSingleConversationViewModel {
    /// Выбранный собеседник. `nil` — никто не выбран, кнопка «Создать» неактивна.
    private(set) var selectedUserId: Int?
    /// `true`, пока выполняется запрос создания переписки.
    private(set) var isCreating = false
    /// Содержимое поля поиска.
    var searchText = ""

    /// Размер страницы списка пользователей.
    static let pageSize = 30
    /// Пауза после ввода в поле поиска, прежде чем уйдёт запрос.
    private let searchDebounce: Duration

    private let list = PaginatedList<UserRowDisplayModel>()
    /// Поисковый запрос, под который загружен текущий список. Следующие страницы продолжают именно его:
    /// `searchText` во время паузы перед поиском уже новый, а курсор `maxId` — ещё от прежней выдачи.
    private var listedQuery = ""
    private let usersService: UsersServiceProtocol
    private let conversationService: ConversationServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let notifications: InAppNotificationServiceProtocol
    private let router: CreateSingleConversationRouter

    /// - Parameters:
    ///   - usersService: сервис списка пользователей.
    ///   - conversationService: сервис переписок — для создания личного диалога.
    ///   - sessionService: сервис сессии; текущий пользователь исключается из списка.
    ///   - notifications: показ ошибок загрузки и создания — поверх листа, в котором открыт экран.
    ///   - router: роутер экрана; через него экран завершается — отменой или созданной перепиской.
    ///   - searchDebounce: пауза после ввода в поле поиска перед запросом.
    init(
        usersService: UsersServiceProtocol,
        conversationService: ConversationServiceProtocol,
        sessionService: SessionServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        router: CreateSingleConversationRouter,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.usersService = usersService
        self.conversationService = conversationService
        self.sessionService = sessionService
        self.notifications = notifications
        self.router = router
        self.searchDebounce = searchDebounce
    }

    /// Пользователи для выбора собеседника; текущий пользователь в список не попадает.
    var users: [UserRowDisplayModel] {
        list.items
    }

    /// `true`, пока грузится первая страница (при открытии, поиске или pull-to-refresh).
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

    /// `true`, если выбран собеседник и переписка ещё не создаётся.
    var isCreateButtonEnabled: Bool {
        guard !isCreating else { return false }
        return selectedUserId != nil
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
        let query = searchText
        let outcome = await list.refresh { context in try await loadPage(context, query: query) }
        if case .applied = outcome {
            listedQuery = query
            keepSelectionIfListed()
        }
        show(outcome)
    }

    /// Начинает загрузку следующей страницы, если показан один из последних пользователей списка.
    /// Страница запрашивается под запрос, по которому загружен список, а не под текущий текст поля поиска.
    /// - Parameter user: пользователь, который появился на экране.
    func prefetchNextPageIfNeeded(currentUser user: UserRowDisplayModel) {
        let query = listedQuery
        list.prefetchNextPageIfNeeded(
            currentItem: user,
            load: { context in try await self.loadPage(context, query: query) },
            onOutcome: show
        )
    }

    /// Запрашивает страницу пользователей и приводит её к строкам списка,
    /// исключая текущего пользователя — переписку с самим собой создать нельзя.
    /// - Parameters:
    ///   - context: курсор `maxId` предыдущей страницы; для первой страницы — `nil`.
    ///   - query: поисковый запрос.
    private func loadPage(
        _ context: PaginationContext,
        query: String
    ) async throws -> PaginatedListPage<UserRowDisplayModel> {
        let page = try await usersService.fetchUsers(query: query, maxId: context.cursor, count: Self.pageSize)
        let currentUserId = sessionService.currentUser?.userId
        return PaginatedListPage(
            items: page.users.filter { $0.userId != currentUserId }.map(UserRowDisplayModel.init),
            hasNext: page.hasNext,
            nextCursor: page.nextMaxId
        )
    }

    /// Показывает сообщение, если загрузка страницы не удалась. Устаревшие ответы игнорируются.
    /// - Parameter outcome: итог загрузки страницы.
    private func show(_ outcome: PaginationOutcome) {
        guard case .failed(let error) = outcome else { return }
        notifications.showError(ErrorMessages.message(for: error))
    }

    /// Сбрасывает выбор, если выбранного пользователя нет в новом списке, — чтобы нельзя было создать
    /// переписку с тем, кого не видно на экране.
    private func keepSelectionIfListed() {
        guard let selectedUserId, !list.contains(id: selectedUserId) else { return }
        self.selectedUserId = nil
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
            notifications.showError(ErrorMessages.message(for: error))
        }
    }
}
