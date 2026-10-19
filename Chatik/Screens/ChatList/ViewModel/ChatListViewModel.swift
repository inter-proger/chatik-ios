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
/// Строки (`conversations`) пересобирает `observeConversations()`: он следит через Observation за списком,
/// собеседниками в кэше пользователей, неотправленными сообщениями, черновиками, языком и днём «сейчас» и применяет изменения не чаще раза
/// в `rowsUpdateInterval`, — частые события (поток сообщений, слияние страниц) не перерисовывают список
/// на каждое изменение.
@MainActor
@Observable
final class ChatListViewModel {
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?
    /// Строки списка, сначала поднявшиеся последними. Обновляются `observeConversations()` не чаще раза
    /// в `rowsUpdateInterval`.
    private(set) var conversations: [ChatRowDisplayModel] = []
    /// «Сейчас» для формата времени строк: от него зависит, какие строки показывают только время («сегодня»).
    /// Хранится, а не берётся из `now()` при каждом чтении — смену дня Observation иначе не заметил бы.
    private(set) var referenceDate: Date

    private let conversationList: ConversationListServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let draftService: MessageDraftServiceProtocol
    private let unsentMessages: UnsentMessagePreviewProviding
    private let localizationService: LocalizationServiceProtocol
    private let router: ChatListRouter
    private let now: () -> Date
    private let makeRow: RowBuilder
    /// Собранные строки по `conversationId` вместе с данными, из которых они собраны: при изменении списка
    /// заново собираются только изменившиеся строки, а не все с форматированием времени. Не наблюдается —
    /// это кэш вычисления, а не состояние экрана.
    @ObservationIgnored private var rowCache: [Int: CachedRow] = [:]
    /// Язык, календарь и день, с которыми собраны строки кэша; сменились — кэш сбрасывается.
    @ObservationIgnored private var rowCacheContext: RowFormatContext?

    private let sleep: Sleep

    /// Минимальный интервал между обновлениями строк списка.
    static let rowsUpdateInterval: Duration = .milliseconds(500)

    /// Ожидание между обновлениями строк; подменяется в тестах.
    typealias Sleep = @MainActor (Duration) async throws -> Void
    /// Собирает строку списка из переписки, собеседника, локального состояния (неотправленное или черновик)
    /// и формата времени.
    typealias RowBuilder = @MainActor (Conversation, CachedUser?, ChatRowLocalPreview?, MessageTimeFormatter) -> ChatRowDisplayModel

    /// - Parameters:
    ///   - conversationList: список переписок.
    ///   - sessionService: текущий пользователь — аватар кнопки профиля.
    ///   - userCache: кэш пользователей — собеседники личных переписок.
    ///   - draftService: черновики — показываются в строке вместо последнего сообщения.
    ///   - unsentMessages: неотправленные сообщения — показываются в строке вместо черновика и последнего сообщения.
    ///   - localizationService: язык форматирования времени.
    ///   - router: переходы с экрана.
    ///   - now: текущее время; подменяется в тестах форматирования.
    ///   - makeRow: сборка строки; подменяется в тестах кэша строк.
    ///   - sleep: ожидание между обновлениями строк; подменяется в тестах.
    init(
        conversationList: ConversationListServiceProtocol,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        draftService: MessageDraftServiceProtocol,
        unsentMessages: UnsentMessagePreviewProviding,
        localizationService: LocalizationServiceProtocol,
        router: ChatListRouter,
        now: @escaping () -> Date = { Date() },
        makeRow: @escaping RowBuilder = { ChatRowDisplayModel(conversation: $0, opponent: $1, localPreview: $2, timeFormatter: $3) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.conversationList = conversationList
        self.sessionService = sessionService
        self.userCache = userCache
        self.draftService = draftService
        self.unsentMessages = unsentMessages
        self.localizationService = localizationService
        self.router = router
        self.now = now
        self.makeRow = makeRow
        self.sleep = sleep
        referenceDate = now()
        // Первый кадр экрана показывает уже имеющийся список (кэш из БД), не дожидаясь наблюдателя.
        conversations = makeRows()
    }

    /// Пересобирает строки при изменении того, из чего они собраны, не чаще раза в `rowsUpdateInterval`, пока
    /// задачу не отменят. Первое изменение после паузы применяется сразу; изменения, пришедшие в течение интервала
    /// после обновления, склеиваются и применяются одним обновлением в его конце. При запуске строки собираются
    /// сразу — экран мог пропустить изменения, пока был скрыт.
    func observeConversations() async {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        var iterator = changes.makeAsyncIterator()
        while !Task.isCancelled {
            let rows = withObservationTracking { makeRows() } onChange: { continuation.yield() }
            if rows != conversations {
                conversations = rows
            }
            do {
                try await sleep(Self.rowsUpdateInterval)
            } catch {
                return
            }
            guard await iterator.next() != nil else { return }
        }
    }

    /// Собирает строки из текущего списка. Строка берётся из кэша, если не изменились ни переписка, ни собеседник,
    /// ни локальное состояние, ни язык, календарь и день формата. Читает список, собеседников, неотправленные
    /// сообщения, черновики, язык и `referenceDate` — по этим чтениям `observeConversations()` узнаёт об изменениях.
    private func makeRows() -> [ChatRowDisplayModel] {
        let context = RowFormatContext(language: localizationService.language, calendar: .current, referenceDate: referenceDate)
        if context != rowCacheContext {
            rowCache = [:]
            rowCacheContext = context
        }
        let timeFormatter = MessageTimeFormatter(locale: context.language.locale, calendar: context.calendar, now: referenceDate)
        var cache: [Int: CachedRow] = [:]
        cache.reserveCapacity(conversationList.conversations.count)
        let rows = conversationList.conversations.map { conversation in
            let opponent = conversation.opponentUserId.map(userCache.user(id:))
            let localPreview = localPreview(for: conversation.id)
            let row = rowCache[conversation.id]?.row(for: conversation, opponent: opponent, localPreview: localPreview)
                ?? makeRow(conversation, opponent, localPreview, timeFormatter)
            cache[conversation.id] = CachedRow(conversation: conversation, opponent: opponent, localPreview: localPreview, row: row)
            return row
        }
        // Кэш держит только строки текущего списка — ушедшие переписки (выход, pull-to-refresh) не копятся.
        rowCache = cache
        return rows
    }

    /// Локальное состояние переписки для превью: незавершённое редактирование важнее неотправленного сообщения,
    /// а оно — черновика. Режим читается через `editingMessageId(for:)`: набор текста правки строку не пересобирает.
    /// - Parameter conversationId: переписка.
    /// - Returns: `nil` — нет ни редактирования, ни неотправленного сообщения, ни черновика.
    private func localPreview(for conversationId: Int) -> ChatRowLocalPreview? {
        guard draftService.editingMessageId(for: conversationId) == nil else { return .editing }
        return unsentMessages.lastFailedText(for: conversationId).map(ChatRowLocalPreview.failed)
            ?? draftService.draft(for: conversationId).map(ChatRowLocalPreview.draft)
    }

    /// `true`, пока идёт стартовая синхронизация: в заголовке вместо названия — «Обновление…».
    var isSyncing: Bool {
        conversationList.isSyncing
    }

    /// `true`, пока грузится следующая страница.
    var isLoadingNextPage: Bool {
        conversationList.isLoadingNextPage
    }

    /// `true`, пока строк нет, а список либо ещё ни разу не загружался с сервера и идёт синхронизация, либо уже
    /// не пуст, но строки его ещё не догнали (обновляются не чаще раза в `rowsUpdateInterval`), — по центру
    /// прелоадер. Пустота берётся из строк: иначе первая страница, пришедшая во время интервала, убрала бы
    /// прелоадер раньше, чем появились строки, и экран остался бы пустым.
    var isLoadingFirstPage: Bool {
        guard conversations.isEmpty else { return false }
        return !conversationList.conversations.isEmpty || (!conversationList.isLoaded && conversationList.isSyncing)
    }

    /// `true`, если чатов действительно нет: список загружен с сервера, пуст и синхронизация не идёт, а строки
    /// уже догнали его — «Нет чатов» не показывается поверх строк, которые ещё не успели исчезнуть.
    /// До первой загрузки пустой список ещё ничего не значит.
    var isEmpty: Bool {
        guard conversations.isEmpty, conversationList.conversations.isEmpty else { return false }
        return conversationList.isLoaded && !conversationList.isSyncing
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

/// Строка списка вместе с данными, из которых она собрана.
private struct CachedRow {
    let conversation: Conversation
    let opponent: CachedUser?
    let localPreview: ChatRowLocalPreview?
    let row: ChatRowDisplayModel

    /// Строка, если она собрана из тех же переписки, собеседника и локального состояния.
    /// - Parameters:
    ///   - conversation: текущая версия переписки.
    ///   - opponent: текущее состояние собеседника в кэше пользователей.
    ///   - localPreview: текущее неотправленное сообщение или черновик переписки.
    /// - Returns: `nil` — строку нужно собрать заново.
    func row(for conversation: Conversation, opponent: CachedUser?, localPreview: ChatRowLocalPreview?) -> ChatRowDisplayModel? {
        guard conversation == self.conversation, opponent == self.opponent, localPreview == self.localPreview else { return nil }
        return row
    }
}

/// То, от чего строка зависит помимо переписки и собеседника: язык строк и формата, календарь и день «сейчас».
/// Внутри одного дня формат времени не меняется — «сегодня», «в этом году» и «раньше» зависят только от дня.
private struct RowFormatContext: Equatable {
    let language: AppLanguage
    let calendar: Calendar
    let day: Date

    init(language: AppLanguage, calendar: Calendar, referenceDate: Date) {
        self.language = language
        self.calendar = calendar
        day = calendar.startOfDay(for: referenceDate)
    }
}
