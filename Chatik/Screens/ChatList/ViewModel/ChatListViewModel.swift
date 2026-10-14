//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана списка чатов: список переписок, переход в профиль, создание личного диалога.
///
/// Список хранит, синхронизирует и пишет в БД `ConversationListService` — сервис уровня приложения, который живёт
/// дольше экрана и сам следит за событиями WebSocket и выходом из аккаунта. ViewModel только готовит строки
/// и передаёт ему действия пользователя.
///
/// Собеседник берётся из кэша пользователей при каждом чтении `conversations`, поэтому строка обновляется сама,
/// когда собеседник догрузится.
@MainActor
@Observable
final class ChatListViewModel {
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?
    /// «Сейчас» для формата времени строк: от него зависит, какие строки показывают только время («сегодня»).
    /// Хранится, а не берётся из `now()` при каждом чтении — смену дня Observation иначе не заметил бы.
    private(set) var referenceDate: Date

    private let conversationList: ConversationListServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let localizationService: LocalizationServiceProtocol
    private let router: ChatListRouter
    private let now: () -> Date

    /// - Parameters:
    ///   - conversationList: список переписок.
    ///   - sessionService: текущий пользователь — аватар кнопки профиля.
    ///   - userCache: кэш пользователей — собеседники личных переписок.
    ///   - localizationService: язык форматирования времени.
    ///   - router: переходы с экрана.
    ///   - now: текущее время; подменяется в тестах форматирования.
    init(
        conversationList: ConversationListServiceProtocol,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        router: ChatListRouter,
        now: @escaping () -> Date = { Date() }
    ) {
        self.conversationList = conversationList
        self.sessionService = sessionService
        self.userCache = userCache
        self.localizationService = localizationService
        self.router = router
        self.now = now
        referenceDate = now()
    }

    /// Переписки текущего пользователя, сначала поднявшиеся последними. Собеседники читаются из кэша
    /// пользователей — Observation отслеживает это чтение, и строки перерисуются, когда собеседники загрузятся.
    var conversations: [ChatRowDisplayModel] {
        let timeFormatter = MessageTimeFormatter(locale: localizationService.language.locale, calendar: .current, now: referenceDate)
        return conversationList.conversations.map { conversation in
            ChatRowDisplayModel(
                conversation: conversation,
                opponent: conversation.opponentUserId.map(userCache.user(id:)),
                timeFormatter: timeFormatter
            )
        }
    }

    /// `true`, пока идёт стартовая синхронизация: в заголовке вместо названия — «Обновление…».
    var isSyncing: Bool {
        conversationList.isSyncing
    }

    /// `true`, пока грузится следующая страница.
    var isLoadingNextPage: Bool {
        conversationList.isLoadingNextPage
    }

    /// `true`, пока список ещё ни разу не загружался с сервера, пуст и идёт синхронизация — по центру прелоадер.
    var isLoadingFirstPage: Bool {
        conversationList.conversations.isEmpty && !conversationList.isLoaded && conversationList.isSyncing
    }

    /// `true`, если чатов действительно нет: список загружен с сервера, пуст и синхронизация не идёт.
    /// До первой загрузки пустой список ещё ничего не значит.
    var isEmpty: Bool {
        conversationList.conversations.isEmpty && conversationList.isLoaded && !conversationList.isSyncing
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

    /// Открытие экрана: синхронизирует список, если в этой сессии синхронизации ещё не было, — например, WebSocket
    /// ещё не подключился или не может подключиться. Ошибку показывает; прерывание новой синхронизацией — нет.
    func loadIfNeeded() async {
        do {
            try await conversationList.synchronizeIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Обновляет «сейчас» для формата времени при открытии экрана и при каждой смене календарного дня, пока задачу
    /// не отменят: после полуночи вчерашние строки должны показать дату, а не только время.
    /// - Parameter notificationCenter: источник `NSCalendarDayChanged`; подменяется в тестах.
    func observeDayChanges(notificationCenter: NotificationCenter = .default) async {
        referenceDate = now()
        for await _ in notificationCenter.notifications(named: .NSCalendarDayChanged) {
            referenceDate = now()
        }
    }

    /// Pull-to-refresh: перезагружает список с первой страницы. Ошибку показывает; прерывание новой
    /// синхронизацией — нет: список и так обновит она.
    func refresh() async {
        do {
            try await conversationList.refresh()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Начинает загрузку следующей страницы, если показана одна из последних переписок списка.
    /// - Parameter conversation: переписка, которая появилась на экране.
    func prefetchNextPageIfNeeded(currentConversation conversation: ChatRowDisplayModel) {
        conversationList.loadNextPageIfNeeded(currentConversationId: conversation.id)
    }

    /// Добавляет только что созданную переписку в список и открывает её. Если она в списке уже есть — сливается
    /// с ней: повторный `createSingle` с тем же собеседником возвращает уже существующую переписку.
    /// - Parameter conversation: переписка, с которой завершился экран создания.
    func didCreateConversation(_ conversation: Conversation) {
        conversationList.apply(conversation)
        router.showConversation(conversation)
    }

    // MARK: - Навигация

    /// Обработчик кнопки-аватара: открывает экран профиля.
    func didTapProfile() {
        router.showProfile()
    }

    /// Обработчик тапа по строке списка: открывает переписку.
    /// - Parameter row: строка, по которой тапнули.
    func didSelectConversation(_ row: ChatRowDisplayModel) {
        guard let conversation = conversationList.conversations.first(where: { $0.id == row.id }) else { return }
        router.showConversation(conversation)
    }

    /// Обработчик пункта «Личный диалог» меню создания: открывает экран создания личного диалога.
    func didTapCreateSingleConversation() {
        router.showCreateSingleConversation()
    }
}
