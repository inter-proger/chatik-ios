//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана списка чатов: постраничный список переписок, переход в профиль, создание личного
/// диалога и выход из аккаунта.
///
/// Список переписок хранит `PaginatedList`: он же отбрасывает устаревшие ответы, не допускает дубликатов
/// и считает сдвиг для следующей страницы. ViewModel остаётся владельцем запроса и текстов ошибок.
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

    private let list = PaginatedList<ChatRowDisplayModel>()
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

    /// Переписки текущего пользователя, сначала самые новые.
    var conversations: [ChatRowDisplayModel] {
        list.items
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
    func loadFirstPage() async {
        show(await list.refresh(load: loadPage))
    }

    /// Начинает загрузку следующей страницы, если показана одна из последних переписок списка.
    /// - Parameter conversation: переписка, которая появилась на экране.
    func prefetchNextPageIfNeeded(currentConversation conversation: ChatRowDisplayModel) {
        list.prefetchNextPageIfNeeded(currentItem: conversation, load: loadPage, onOutcome: show)
    }

    /// Добавляет только что созданную переписку в начало списка. Если она там уже есть — не дублирует:
    /// повторный `createSingle` с тем же собеседником возвращает уже существующую переписку.
    /// - Parameter conversation: переписка, с которой завершился экран создания.
    func didCreateConversation(_ conversation: Conversation) {
        list.insertIfAbsent(ChatRowDisplayModel(conversation: conversation))
    }

    /// Запрашивает страницу переписок и приводит её к строкам списка.
    /// - Parameter context: сколько переписок уже получено — от этого числа идёт сдвиг выдачи.
    private func loadPage(_ context: PaginationContext) async throws -> PaginatedListPage<ChatRowDisplayModel> {
        let page = try await conversationService.fetchConversations(
            offset: context.isFirstPage ? nil : context.loadedCount,
            count: Self.pageSize
        )
        return PaginatedListPage(items: page.conversations.map(ChatRowDisplayModel.init), hasNext: page.hasNext)
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
