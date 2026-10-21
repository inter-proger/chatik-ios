//
//  ChatViewModel.swift
//  Chatik
//

import Foundation
import os

/// Состояние экрана переписки: лента сообщений, ввод и отправка сообщения.
///
/// Ленту держит `MessagesListService` — он показывает кэш из БД, синхронизирует его с сервером, подгружает старые
/// сообщения и накладывает отправленные. ViewModel получает от него снимки и собирает из них ленту для
/// отображения — секции по дням (`sections`) — не чаще раза в `messagesUpdateInterval`: частые события
/// не перерисовывают ленту на каждое изменение. Своё отправленное сообщение и нажатие «Отправить» показываются сразу.
/// Сборка (форматирование времени и заголовков дней, серии отправителей) идёт вне main — на main только сбор
/// входных данных и присвоение результата. Смена языка и значимое изменение времени (полночь, часовой пояс)
/// пересобирают ленту: «Сегодня» становится «Вчера» без переоткрытия экрана.
///
/// `observeMessages()` может выполняться в нескольких копиях одновременно: SwiftUI запускает новый `.task`
/// при повторном появлении экрана, когда старый ещё завершается. Лента запускается с первым наблюдателем
/// и останавливается с последним, а запуск и остановка выполняются строго по очереди.
///
/// Отправкой занимается общая для всех переписок очередь (`MessageSendQueue`): экран ставит в неё сообщения,
/// показывает её сообщения этой переписки внизу ленты (в статусах «отправляется» и «не отправлено») и передаёт ей
/// действия с неотправленными. Отправка продолжается и после закрытия экрана.
///
/// Текст поля ввода — черновик (`MessageDraftService`): при создании экрана в поле подставляется сохранённый
/// черновик, каждое изменение текста меняет черновик в памяти (список чатов видит его сразу), а в БД он уходит
/// в точках сохранения — уход с экрана, уход приложения в неактивное состояние или в фон (их сообщает View),
/// отправка. Черновик принадлежит пользователю, открывшему экран: экран может уйти уже после выхода из аккаунта.
///
/// Своё доставленное сообщение можно отредактировать (раздел «Редактирование»): в режиме редактирования текст поля —
/// текст правки, а черновик ждёт в сервисе черновиков нетронутым и возвращается в поле после выхода из режима.
/// Правку хранит сервис черновиков рядом с черновиком, а запрос выполняет `MessageEditService` — он переживает уход
/// с экрана. Исход запроса — своего или начатого на прошлом открытии экрана — ждёт только `observeEditSubmission`,
/// задача которого живёт, пока экран показан. Ошибка, которую экран не успел показать, остаётся в сервисе до
/// следующего открытия.
///
/// Прочтение (раздел «Прочтение», решения 6 и 10 в `docs/unread-messages.md`): переписка отмечается прочитанной до
/// самого нового показанного серверного сообщения, когда экран в активной сцене, лента внизу и загружена, — одно
/// правило покрывает вход, входящее у нижнего края, докрутку до низа и возврат из фона. Заголовок непрочитанных
/// стоит над первым сообщением после границы `unreadBoundary`: при входе это указатель до первой отметки, при новом
/// сообщении собеседника вне видимости — сообщение перед ним; дальше граница не двигается до повторного входа
/// или pull-to-refresh. Положение ленты и активность сцены сообщает View.
///
/// Тексты и производные данные — в `ChatViewModel+Texts`.
@MainActor
@Observable
final class ChatViewModel {
    /// Текст в поле ввода. Каждое изменение меняет в памяти черновик или, в режиме редактирования, текст правки.
    var messageText = "" {
        didSet { updateDraft() }
    }
    /// Режим поля ввода. Хранится, а не вычисляется по сервису черновиков: при выходе из аккаунта сервис очищает
    /// память, и вычисляемый режим принял бы выход за выключение редактирования. Меняется в явных точках — включение,
    /// крестик, подтверждение без изменений и успех запроса.
    private(set) var inputMode = ChatInputMode.compose
    /// Текст редактируемого сообщения для плашки: из ленты, если сообщение в её окне (правка с другого устройства
    /// обновит плашку), иначе — на момент включения режима. `nil` — режим выключен. Хранится, а не вычисляется
    /// по `serverMessages`: тот не наблюдается, и View не узнала бы о правке.
    private(set) var editedMessageText: String?
    /// Растёт, когда полю ввода нужно вернуть фокус: после ошибки запроса правки клавиатура пряталась на время
    /// запроса и возвращается, чтобы правку можно было сразу исправить. Счётчик, а не флаг: повторная ошибка тоже
    /// возвращает фокус, а View не нужно его сбрасывать.
    private(set) var inputFocusRequest = 0
    /// Лента по дням, сначала самые новые. Обновляется `observeMessages()` не чаще раза
    /// в `messagesUpdateInterval`.
    private(set) var sections: [MessageDaySectionDisplayModel] = []
    /// Идёт синхронизация с сервером: в заголовке — индикатор «Обновление…».
    private(set) var isSyncing = false
    /// Грузятся более старые сообщения.
    private(set) var isLoadingOlder = false
    /// Есть более старые сообщения — в БД или на сервере.
    private(set) var hasOlder = false
    /// Окно ленты прочитано из БД хотя бы раз: до этого пустая лента — ещё не «сообщений нет».
    private(set) var isLoaded = false
    /// Граница непрочитанных: id последнего сообщения, прочитанного до заголовка «Непрочитанные сообщения».
    /// `nil` — заголовка нет.
    private(set) var unreadBoundary: Int?
    /// Растёт, когда новое сообщение появляется у нижнего края ленты: View анимирует это изменение ленты.
    /// Подгрузка старых, правка, смена статуса и вставка при отлистанной ленте его не меняют.
    private(set) var insertionAnimationToken = 0
    /// Растёт, когда ленту нужно вернуть вниз: своё сообщение при отлистанной ленте.
    private(set) var scrollToBottomRequest = 0

    /// Минимальный интервал между обновлениями ленты.
    static let messagesUpdateInterval: Duration = .milliseconds(500)
    /// За сколько сообщений до конца ленты начинать подгрузку более старых.
    static let prefetchThreshold = 10

    let conversation: Conversation
    let sessionService: SessionServiceProtocol
    let userCache: UserCacheServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let messageTextValidator: MessageTextValidatorProtocol
    let messageSendQueue: MessageSendQueueProtocol
    let editService: MessageEditServiceProtocol
    let now: () -> Date
    private let draftService: MessageDraftServiceProtocol
    /// Пользователь, открывший экран, — владелец черновика; `nil` — сессии нет, черновик не меняется.
    /// Задаётся в конце `init`, после подстановки черновика: подстановка не возвращается в сервис через `didSet`.
    @ObservationIgnored private var draftUserId: Int?
    /// Идёт замена текста поля при смене режима: `didSet` не записывает подставленный текст в черновик или правку.
    @ObservationIgnored private var isReplacingInput = false
    /// Идущий `observeEditSubmission`: ему `submitEdit` сообщает о начатом запросе; `nil` — экран не показан.
    @ObservationIgnored private var editSubmissionObserver: EditSubmissionObserver?
    /// Календарь, по которому лента делится на дни. Функция, а не значение: после смены часового пояса
    /// `Calendar.current` уже другой.
    private let calendar: () -> Calendar
    private let messagesList: MessagesListServiceProtocol
    private let dateHeaderFormatterProvider: MessageDateHeaderFormatterProviding
    private let timeChangeService: SignificantTimeChangeServiceProtocol
    private let notifications: InAppNotificationServiceProtocol
    /// Прочтение переписки и отметка прочтения.
    let readStates: ConversationReadStateProviding
    private let sleep: Sleep

    /// Сообщения с сервера из последнего снимка ленты. Не наблюдается: об изменении `observeMessages()` узнаёт
    /// из снимка.
    @ObservationIgnored private var serverMessages: [Message] = []
    /// Позиции сообщений ленты в плоском порядке, от самого нового, — для подгрузки старых.
    @ObservationIgnored private var messagePositions: [MessageClientKey: Int] = [:]
    /// `isLoaded` из последнего снимка; на экран попадает вместе с собранными из него сообщениями.
    @ObservationIgnored private var isServerWindowLoaded = false
    /// Отправители, загрузка которых уже запрошена.
    @ObservationIgnored private var requestedSenderIds: Set<Int> = []
    /// Циклы обновления идущих `observeMessages()`.
    @ObservationIgnored private var updateLoops: [MessagesUpdateLoop] = []
    /// Последний запуск или остановка ленты: следующий начинается только после него.
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    /// Подписка на снимки ленты, пока лента запущена.
    @ObservationIgnored private var snapshotsTask: Task<Void, Never>?
    /// Подписка на значимые изменения времени, пока лента запущена.
    @ObservationIgnored private var timeChangesTask: Task<Void, Never>?
    /// Сцена экрана активна — сообщает View.
    @ObservationIgnored private var isSceneActive = false
    /// Лента внизу: последнее сообщение видно — сообщает View.
    @ObservationIgnored private var isAtBottom = true
    /// Граница непрочитанных уже вычислена при входе или pull-to-refresh: дальше её меняет только новое сообщение.
    @ObservationIgnored private var isUnreadBoundaryResolved = false
    /// Самое новое серверное сообщение последнего снимка — чтобы заметить новые.
    @ObservationIgnored private var snapshotNewestServerId: Int?
    /// Самое новое серверное сообщение показанной ленты — до него отмечается прочтение.
    @ObservationIgnored private var displayedNewestServerId: Int?
    /// Все неотправленные сообщения, побывавшие в ленте: подтверждённое сервером своё сообщение не анимируется второй
    /// раз — у него тот же `id`.
    @ObservationIgnored private var knownOutgoingKeys: Set<MessageClientKey> = []

    /// Ожидание между обновлениями ленты; подменяется в тестах.
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// - Parameters:
    ///   - conversation: открытая переписка.
    ///   - messagesList: лента переписки.
    ///   - messageSendQueue: очередь отправки сообщений.
    ///   - editService: отправка правок сообщений.
    ///   - sessionService: сессия — по ней сообщения делятся на исходящие и входящие; её пользователь — владелец
    ///     черновика.
    ///   - draftService: черновики и незавершённые правки — текст поля ввода между открытиями экрана.
    ///   - userCache: кэш пользователей — имена собеседника и отправителей.
    ///   - localizationService: язык форматирования времени и заголовков дней.
    ///   - messageTextValidator: проверка текста перед отправкой.
    ///   - dateHeaderFormatterProvider: форматтеры заголовков дней по языку.
    ///   - timeChangeService: полночь, смена часового пояса и перевод часов — пересобирают заголовки.
    ///   - notifications: показ ошибок ленты и правки.
    ///   - readStates: прочтение переписки — граница непрочитанных, счётчик кнопки «вниз» и отметка прочтения.
    ///   - now: текущее время; подменяется в тестах форматирования.
    ///   - calendar: календарь устройства; подменяется в тестах, чтобы деление на дни не зависело от устройства.
    ///   - sleep: ожидание между обновлениями ленты; подменяется в тестах.
    init(
        conversation: Conversation,
        messagesList: MessagesListServiceProtocol,
        messageSendQueue: MessageSendQueueProtocol,
        editService: MessageEditServiceProtocol,
        sessionService: SessionServiceProtocol,
        draftService: MessageDraftServiceProtocol,
        userCache: UserCacheServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        messageTextValidator: MessageTextValidatorProtocol,
        dateHeaderFormatterProvider: MessageDateHeaderFormatterProviding,
        timeChangeService: SignificantTimeChangeServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        readStates: ConversationReadStateProviding,
        now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { .current },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.conversation = conversation
        self.messagesList = messagesList
        self.messageSendQueue = messageSendQueue
        self.editService = editService
        self.sessionService = sessionService
        self.draftService = draftService
        self.userCache = userCache
        self.localizationService = localizationService
        self.messageTextValidator = messageTextValidator
        self.dateHeaderFormatterProvider = dateHeaderFormatterProvider
        self.timeChangeService = timeChangeService
        self.notifications = notifications
        self.readStates = readStates
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
        // Только чтение: SwiftUI может создать ViewModel несколько раз и оставить первый экземпляр.
        if let edit = draftService.edit(for: conversation.conversationId) {
            inputMode = .editing(messageId: edit.messageId, originalText: edit.originalText)
            editedMessageText = edit.originalText
            messageText = edit.text
        } else {
            messageText = draftService.draft(for: conversation.conversationId) ?? ""
        }
        draftUserId = sessionService.currentUser?.userId
    }

    // MARK: - Лента

    /// Запускает ленту и пересобирает сообщения при изменениях, пока задачу не отменят (уход с экрана); затем
    /// останавливает ленту — идущая синхронизация отменяется и снимает аренду очереди событий. Лента запускается
    /// первым наблюдателем и останавливается последним.
    func observeMessages() async {
        let loop = MessagesUpdateLoop()
        updateLoops.append(loop)
        if updateLoops.count == 1 {
            await performLifecycle { await $0.startList() }
        }
        await runUpdates(loop)
        updateLoops.removeAll { $0 === loop }
        guard updateLoops.isEmpty else { return }
        await performLifecycle { await $0.stopList() }
    }

    /// Выполняет запуск или остановку ленты после предыдущих. Задача не наследует отмену наблюдателя: остановка
    /// должна пройти и при уходе с экрана.
    /// - Parameter operation: запуск или остановка.
    private func performLifecycle(_ operation: @escaping @MainActor (ChatViewModel) async -> Void) async {
        let previous = lifecycle
        let task = Task { [self] in
            await previous?.value
            await operation(self)
        }
        lifecycle = task
        await task.value
    }

    /// Подписывается на снимки ленты и на изменения времени и запускает ленту.
    private func startList() async {
        let snapshots = await messagesList.snapshots()
        snapshotsTask = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
            }
        }
        let timeChanges = timeChangeService.changes()
        // Новый день или часовой пояс: `now()` берётся заново, секции и заголовки пересобираются без паузы.
        timeChangesTask = Task { [weak self] in
            for await _ in timeChanges {
                self?.requestImmediateUpdate()
            }
        }
        await messagesList.start()
    }

    /// Отписывается от снимков и изменений времени и останавливает ленту.
    private func stopList() async {
        snapshotsTask?.cancel()
        snapshotsTask = nil
        timeChangesTask?.cancel()
        timeChangesTask = nil
        await messagesList.stop()
    }

    /// Пересобирает сообщения при изменении того, из чего они собраны, не чаще раза в `messagesUpdateInterval`.
    /// Первое изменение после паузы применяется сразу, изменения в течение интервала склеиваются; срочное изменение
    /// прерывает паузу.
    /// - Parameter loop: цикл обновления этого наблюдателя.
    private func runUpdates(_ loop: MessagesUpdateLoop) async {
        var iterator = loop.changes.makeAsyncIterator()
        while !Task.isCancelled {
            loop.beginUpdate()
            let input = trackBuildInput(for: loop)
            let isWindowLoaded = isServerWindowLoaded
            loadSenders(ids: input.senders.keys)
            let feed = await Self.buildFeed(input)
            updateInsertionAnimation(input: input)
            messagePositions = feed.positions
            if feed.sections != sections {
                sections = feed.sections
            }
            isLoaded = isWindowLoaded
            displayedNewestServerId = feed.newestServerMessageId
            markReadIfNeeded()
            await loop.waitBeforeNextUpdate(sleep: sleep)
            guard await iterator.next() != nil else { return }
        }
    }

    /// Читает входные данные сборки. Наблюдение Observation ставится, только если прежнее уже сработало: обновления
    /// по снимкам не должны копить регистрации, которые живут до изменения наблюдаемых свойств.
    /// - Parameter loop: цикл обновления, которому Observation сообщает об изменении.
    private func trackBuildInput(for loop: MessagesUpdateLoop) -> MessagesBuildInput {
        guard loop.armTracking() else { return makeBuildInput() }
        let isTracking = loop.isTracking
        let signal = loop.signal
        return withObservationTracking { makeBuildInput() } onChange: {
            isTracking.withLock { $0 = false }
            signal.yield()
        }
    }

    /// Применяет снимок ленты: состояние загрузки и ошибки — сразу, сообщения — через интервал обновления.
    /// - Parameter snapshot: снимок.
    private func apply(_ snapshot: MessagesListSnapshot) {
        isSyncing = snapshot.isSyncing
        isLoadingOlder = snapshot.isLoadingOlder
        hasOlder = snapshot.hasOlder
        if let failure = snapshot.failure {
            notifications.showError(ErrorMessages.message(for: failure))
        }
        serverMessages = snapshot.messages
        refreshEditedMessageText()
        isServerWindowLoaded = snapshot.isLoaded
        let hasNewMessages = handleNewMessages(in: snapshot.messages)
        // Новое сообщение у нижнего края не ждёт паузы: оно появляется с анимацией, и задержка была бы заметна.
        if snapshot.isUrgent || (hasNewMessages && isAtBottom) {
            requestImmediateUpdate()
        } else {
            updateLoops.forEach { $0.signalChange() }
        }
    }

    /// Обновляет ленту сразу, прерывая паузу между обновлениями.
    private func requestImmediateUpdate() {
        updateLoops.forEach { $0.signalUrgentChange() }
    }

    /// Синхронизация по pull-to-refresh: ждёт её окончания, ошибка придёт в снимке. Граница непрочитанных после неё
    /// вычисляется заново, как при входе.
    func refresh() async {
        await messagesList.synchronize()
        isUnreadBoundaryResolved = false
        markReadIfNeeded()
    }

    /// Начинает загрузку более старых сообщений, если показано одно из самых старых.
    /// - Parameter message: сообщение, которое появилось на экране.
    func prefetchOlderIfNeeded(currentMessage message: MessageDisplayModel) {
        guard hasOlder, !isLoadingOlder,
              let index = messagePositions[message.id],
              index >= messagePositions.count - Self.prefetchThreshold else { return }
        Task { await messagesList.loadOlder() }
    }

    // MARK: - Сборка сообщений

    /// Входные данные сборки: читаются на main, и по этим чтениям Observation сообщает об изменениях. Чтение
    /// `language` тоже наблюдается — смена языка пересобирает ленту с форматтером заголовков нового языка.
    private func makeBuildInput() -> MessagesBuildInput {
        let outgoing = outgoingMessages
        let senderIds = Set(serverMessages.map(\.senderId) + outgoing.map(\.senderId))
        let locale = localizationService.language.locale
        let calendar = calendar()
        return MessagesBuildInput(
            serverMessages: serverMessages,
            outgoing: outgoing,
            senders: Dictionary(uniqueKeysWithValues: senderIds.map { ($0, cachedSender(id: $0)) }),
            unreadBoundary: unreadBoundary,
            hasOlder: hasOlder,
            context: MessageDisplayContext(
                currentUserId: sessionService.currentUser?.userId,
                locale: locale,
                calendar: calendar,
                now: now(),
                strings: .current,
                dateHeaderFormatter: dateHeaderFormatterProvider.formatter(locale: locale, calendar: calendar)
            )
        )
    }

    /// Собирает ленту для отображения вне main.
    /// - Parameter input: входные данные.
    /// - Returns: секции по дням, сначала самые новые, и позиции сообщений.
    @concurrent
    nonisolated static func buildFeed(_ input: MessagesBuildInput) async -> MessagesFeed {
        input.makeFeed()
    }

    /// Запускает загрузку отправителей, которых ещё не запрашивали, — для их имён и аватаров. Текущий пользователь
    /// не запрашивается: он берётся из сессии. Лента не ждёт загрузки — пока отправителя нет, вместо имени заглушка.
    /// - Parameter ids: отправители сообщений ленты.
    private func loadSenders(ids: some Collection<Int>) {
        let currentUserId = sessionService.currentUser?.userId
        let newIds = Set(ids).subtracting(requestedSenderIds).filter { $0 != currentUserId }.sorted()
        guard !newIds.isEmpty else { return }
        requestedSenderIds.formUnion(newIds)
        Task { await userCache.loadUsers(ids: newIds) }
    }

    // MARK: - Отправка

    /// Обработчик кнопки отправки: в режиме редактирования подтверждает правку, иначе ставит сообщение в очередь
    /// и сразу очищает поле. Сообщение появляется внизу ленты в статусе «отправляется» — без паузы обновления.
    func didTapSend() {
        guard isSendEnabled else { return }
        guard inputMode == .compose else {
            submitEdit()
            return
        }
        messageSendQueue.enqueue(text: messageText, conversationId: conversation.conversationId)
        messageText = ""
        if let draftUserId {
            draftService.remove(conversationId: conversation.conversationId, userId: draftUserId)
        }
        requestScrollToBottomIfNeeded()
        requestImmediateUpdate()
    }

    // MARK: - Прочтение

    /// Сцена экрана стала активной или неактивной (шторка, фон, неактивная сцена iPad).
    /// - Parameter isActive: `scenePhase == .active` сцены экрана.
    func setSceneActive(_ isActive: Bool) {
        guard isActive != isSceneActive else { return }
        isSceneActive = isActive
        markReadIfNeeded()
    }

    /// Лента дошла до низа или ушла от него.
    /// - Parameter atBottom: последнее сообщение видно.
    func setAtBottom(_ atBottom: Bool) {
        guard atBottom != isAtBottom else { return }
        isAtBottom = atBottom
        markReadIfNeeded()
    }

    /// Правило прочтения (решение 6): экран в активной сцене, лента внизу, загружена и не идёт синхронизация — тогда
    /// переписка отмечается прочитанной до самого нового показанного серверного сообщения. Повторы отсекает сервис
    /// прочтения. Первая отметка сначала фиксирует границу непрочитанных.
    private func markReadIfNeeded() {
        guard isSceneActive, isAtBottom, isLoaded, !isSyncing, let newest = displayedNewestServerId else { return }
        resolveUnreadBoundaryIfNeeded()
        readStates.markRead(conversationId: conversation.conversationId, messageId: newest)
    }

    /// Прочтение переписки: из сервиса прочтения (список чатов или последний `ReadInfo` по ней), а пока оно там
    /// неизвестно — из переписки, с которой открыт экран.
    var currentReadState: ConversationReadState {
        readStates.readState(conversationId: conversation.conversationId) ?? conversation.readState
    }

    /// Фиксирует границу непрочитанных при входе (и после pull-to-refresh) — по подтверждённому указателю до первой
    /// отметки прочтения. Непрочитанных нет — заголовка нет.
    private func resolveUnreadBoundaryIfNeeded() {
        guard !isUnreadBoundaryResolved else { return }
        isUnreadBoundaryResolved = true
        let readState = currentReadState
        setUnreadBoundary(readState.unreadCount > 0 ? readState.lastReadMessageId : nil)
    }

    /// Меняет границу непрочитанных и сразу пересобирает ленту: заголовок не ждёт паузы обновления.
    /// - Parameter boundary: новая граница.
    private func setUnreadBoundary(_ boundary: Int?) {
        guard boundary != unreadBoundary else { return }
        unreadBoundary = boundary
        requestImmediateUpdate()
    }

    /// Разбирает новые серверные сообщения снимка: своё при отлистанной ленте возвращает её вниз, сообщение
    /// собеседника вне видимости закрепляет заголовок непрочитанных над собой, если его ещё нет.
    /// - Parameter messages: сообщения снимка, сначала самые новые.
    /// - Returns: `true` — в снимке есть сообщения новее прежнего снимка.
    private func handleNewMessages(in messages: [Message]) -> Bool {
        let previousNewest = snapshotNewestServerId
        snapshotNewestServerId = messages.first?.messageId
        guard let previousNewest, let newest = messages.first?.messageId, newest > previousNewest else { return false }
        let newMessages = messages.prefix { $0.messageId > previousNewest }
        let currentUserId = sessionService.currentUser?.userId
        if newMessages.contains(where: { $0.senderId == currentUserId }) {
            requestScrollToBottomIfNeeded()
        }
        if !isAtBottom, isUnreadBoundaryResolved, unreadBoundary == nil,
           newMessages.contains(where: { $0.senderId != currentUserId }) {
            setUnreadBoundary(previousNewest)
        }
        return true
    }

    /// Просит View вернуть ленту вниз, если она отлистана.
    private func requestScrollToBottomIfNeeded() {
        guard !isAtBottom else { return }
        scrollToBottomRequest += 1
    }

    /// Анимирует изменение ленты, если у нижнего края появилось новое сообщение: серверное новее показанного
    /// (кроме подтверждения своего неотправленного — у него тот же `id`) или новое неотправленное.
    /// - Parameter input: входные данные собираемой ленты.
    private func updateInsertionAnimation(input: MessagesBuildInput) {
        let outgoingKeys = Set(input.outgoing.map(\.clientKey))
        let hasNewOutgoing = !outgoingKeys.isSubset(of: knownOutgoingKeys)
        knownOutgoingKeys.formUnion(outgoingKeys)
        // До первой показанной ленты вставок нет: это загрузка экрана.
        guard isAtBottom, isLoaded else { return }
        let previousNewest = displayedNewestServerId ?? 0
        let hasNewServer = input.serverMessages.prefix { $0.messageId > previousNewest }
            .contains { !knownOutgoingKeys.contains($0.clientKey) }
        guard hasNewOutgoing || hasNewServer else { return }
        insertionAnimationToken += 1
    }

    // MARK: - Черновик

    /// Записывает в БД черновик или, в режиме редактирования, текст правки — точка сохранения: уход с экрана, уход
    /// приложения в неактивное состояние или в фон. Повторное сохранение без изменений в БД не пишет.
    func saveDraft() {
        guard let draftUserId else { return }
        switch inputMode {
        case .compose:
            draftService.save(text: messageText, conversationId: conversation.conversationId, userId: draftUserId)
        case let .editing(messageId, originalText):
            let edit = MessageEditDraft(messageId: messageId, originalText: originalText, text: messageText)
            draftService.saveEdit(edit, conversationId: conversation.conversationId, userId: draftUserId)
        }
    }

    /// Меняет в памяти черновик или текст правки после изменения поля ввода. Подстановка текста при смене режима
    /// не записывается: иначе черновик стал бы текстом правки или наоборот.
    private func updateDraft() {
        guard let draftUserId, !isReplacingInput else { return }
        switch inputMode {
        case .compose:
            draftService.update(text: messageText, conversationId: conversation.conversationId, userId: draftUserId)
        case .editing:
            draftService.updateEdit(text: messageText, conversationId: conversation.conversationId, userId: draftUserId)
        }
    }

    /// Подставляет текст в поле ввода, не записывая его в черновик или правку.
    /// - Parameter text: новый текст поля.
    private func replaceInput(with text: String) {
        isReplacingInput = true
        messageText = text
        isReplacingInput = false
    }

    /// Меняет режим поля ввода и текст плашки.
    /// - Parameter mode: новый режим.
    private func setInputMode(_ mode: ChatInputMode) {
        guard mode != inputMode else { return }
        inputMode = mode
        refreshEditedMessageText()
    }

    /// Обновляет текст плашки по режиму и ленте. Присваивает только при изменении: снимки без правки
    /// не перерисовывают панель ввода.
    private func refreshEditedMessageText() {
        let text: String?
        switch inputMode {
        case .compose:
            text = nil
        case let .editing(messageId, originalText):
            text = serverMessages.first { $0.messageId == messageId }?.text ?? originalText
        }
        guard text != editedMessageText else { return }
        editedMessageText = text
    }

    // MARK: - Редактирование

    /// Обработчик пункта меню сообщения: редактирование включает режим, повтор и удаление неотправленного
    /// передаются очереди отправки.
    /// - Parameters:
    ///   - action: выбранное действие.
    ///   - message: сообщение, у которого открыто меню.
    func didSelectAction(_ action: MessageAction, for message: MessageDisplayModel) {
        switch action {
        case .edit:
            beginEditing(message)
        case .retrySending:
            messageSendQueue.retry(clientId: message.id.clientId)
        case .deleteUnsent:
            messageSendQueue.delete(clientId: message.id.clientId)
        }
    }

    /// Включает режим редактирования: черновик уходит в БД (точка сохранения) и остаётся нетронутым, в поле
    /// подставляется текст сообщения. При уже включённом режиме ничего не делает — действия в это время скрыты.
    /// - Parameter displayModel: редактируемое сообщение ленты.
    private func beginEditing(_ displayModel: MessageDisplayModel) {
        guard inputMode == .compose, let draftUserId,
              let message = serverMessages.first(where: { $0.clientKey == displayModel.id }) else { return }
        let conversationId = conversation.conversationId
        draftService.save(text: messageText, conversationId: conversationId, userId: draftUserId)
        draftService.beginEditing(messageId: message.messageId, originalText: message.text, conversationId: conversationId, userId: draftUserId)
        guard let edit = draftService.edit(for: conversationId), edit.messageId == message.messageId else {
            Logger.chat.error("Режим редактирования не включён: сервис черновиков отказал")
            return
        }
        setInputMode(.editing(messageId: edit.messageId, originalText: edit.originalText))
        replaceInput(with: edit.text)
    }

    /// Крестик на плашке: выключает режим редактирования и возвращает в поле черновик. Во время запроса крестик
    /// скрыт, и вызов ничего не делает.
    func cancelEditing() {
        guard case let .editing(messageId, _) = inputMode, !isEditSubmitting, let draftUserId else { return }
        draftService.endEditing(messageId: messageId, conversationId: conversation.conversationId, userId: draftUserId)
        switchToCompose()
    }

    /// Подтверждение правки. Текст, совпадающий с текущим текстом сообщения после обрезки, закрывает режим без
    /// запроса. Иначе текст правки уходит в БД и запускается запрос; кнопка и поле блокируются сразу, а результат
    /// приходит через `observeEditSubmission`.
    private func submitEdit() {
        guard case let .editing(messageId, originalText) = inputMode, let draftUserId else { return }
        let conversationId = conversation.conversationId
        guard Self.trimmed(messageText) != Self.trimmed(editedMessageText ?? originalText) else {
            draftService.endEditing(messageId: messageId, conversationId: conversationId, userId: draftUserId)
            switchToCompose()
            return
        }
        let edit = MessageEditDraft(messageId: messageId, originalText: originalText, text: messageText)
        draftService.saveEdit(edit, conversationId: conversationId, userId: draftUserId)
        guard editService.submit(conversationId: conversationId, userId: draftUserId) != nil else {
            Logger.chat.error("Запрос правки не начат: сервис правок отказал")
            return
        }
        editSubmissionObserver?.continuation.yield()
    }

    /// Ждёт исходов запросов правки, пока экран показан, — для `.task` экрана. Сначала — запроса, начатого
    /// на прошлом открытии (или его непоказанной ошибки), затем — каждого запроса, начатого `submitEdit`.
    /// Отмена задачи (уход с экрана) прекращает ожидание и закрывает стрим сигналов, а ошибка остаётся в сервисе
    /// до следующего открытия.
    func observeEditSubmission() async {
        let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observer = EditSubmissionObserver(id: UUID(), continuation: continuation)
        editSubmissionObserver = observer
        defer {
            continuation.finish()
            // Новый `.task` повторно показанного экрана мог уже поставить своего наблюдателя — его не трогаем.
            if editSubmissionObserver?.id == observer.id {
                editSubmissionObserver = nil
            }
        }
        continuation.yield()
        for await _ in requests {
            await awaitEditSubmission()
        }
    }

    /// Ждёт ли экран исходов запросов правки (`observeEditSubmission` запущен).
    var isObservingEditSubmissions: Bool {
        editSubmissionObserver != nil
    }

    /// Дожидается запроса правки и применяет исход, если экран ещё показан. Успех (или отсутствие запроса) сверяет
    /// режим с сервисом: успешный запрос выключил режим, и в поле возвращается черновик. Ошибка забирается
    /// из сервиса и показывается, режим остаётся. Отмена выходом из аккаунта не показывается и режим не трогает:
    /// сервис черновиков к этому моменту уже очистил память.
    private func awaitEditSubmission() async {
        let conversationId = conversation.conversationId
        do {
            try await editService.waitForSubmission(conversationId: conversationId)
        } catch is CancellationError {
            return
        } catch {
            // Ошибка ждёт в сервисе и забирается ниже — только если экран ещё показан.
        }
        guard !Task.isCancelled else { return }
        if let failure = editService.takeFailure(conversationId: conversationId) {
            notifications.showError(ErrorMessages.message(for: failure))
            requestInputFocusIfEditing()
            return
        }
        syncInputModeWithService()
    }

    /// Возвращает фокус в поле ввода, если режим редактирования ещё включён: правку можно сразу исправить.
    private func requestInputFocusIfEditing() {
        guard isEditing else { return }
        inputFocusRequest += 1
    }

    /// Выключает режим, если сервис черновиков уже выключил его, — после успешного запроса.
    private func syncInputModeWithService() {
        guard inputMode != .compose, draftService.editingMessageId(for: conversation.conversationId) == nil else { return }
        switchToCompose()
    }

    /// Переключает поле в режим нового сообщения и возвращает в него черновик.
    private func switchToCompose() {
        setInputMode(.compose)
        replaceInput(with: draftService.draft(for: conversation.conversationId) ?? "")
    }

    /// Текст без краевых пробелов и невидимых символов — так же сервер сравнивает правку с текущим текстом.
    /// - Parameter text: текст.
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: MessageTextValidator.trimmedCharacters)
    }
}

/// Наблюдатель исходов запросов правки — один на показ экрана.
private struct EditSubmissionObserver {
    /// Отличает наблюдателя повторного показа экрана от завершающегося прежнего.
    let id: UUID
    /// Сигналы о запросах, начатых `submitEdit`.
    let continuation: AsyncStream<Void>.Continuation
}

extension Logger {
    /// Лог экрана переписки: сбои, которые не показываются пользователю, но не должны теряться молча.
    static let chat = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Chat")
}

/// Всё, из чего собирается лента, — значениями, чтобы сборка шла вне main.
struct MessagesBuildInput: Sendable {
    /// Сообщения с сервера, сначала самые новые.
    let serverMessages: [Message]
    /// Неотправленные сообщения переписки, сначала самые старые.
    let outgoing: [OutgoingMessage]
    /// Отправители по идентификатору.
    let senders: [Int: CachedUser]
    /// Граница непрочитанных: id последнего сообщения, прочитанного до заголовка. `nil` — заголовка нет.
    let unreadBoundary: Int?
    /// Есть ли сообщения старше окна: без них заголовок над самым старым загруженным мог бы оказаться не на месте.
    let hasOlder: Bool
    let context: MessageDisplayContext

    /// Лента для отображения, сначала самые новые: неотправленные — в самом низу ленты (в начале массива), под
    /// всеми сообщениями с сервера. Неотправленное сообщение, серверная версия которого уже в ленте, не показывается:
    /// очередь и лента узнают о подтверждении независимо, и иначе одно сообщение попало бы в ленту дважды с одним
    /// `id`.
    ///
    /// Сообщения режутся на подряд идущие серии одного дня — без глобальной группировки: вчерашнее неотправленное
    /// сообщение остаётся внизу, под сегодняшними, во второй секции того же дня. Аватар и имя отправителя есть
    /// только у первого сообщения серии подряд от одного отправителя внутри секции.
    func makeFeed() -> MessagesFeed {
        let sentKeys = Set(serverMessages.map(\.clientKey))
        let pending = outgoing.filter { !sentKeys.contains($0.clientKey) }
        let items = pending.reversed().map(ChatFeedItem.outgoing) + serverMessages.map(ChatFeedItem.sent)
        let runs = dayRuns(of: items)
        let ids = sectionIDs(of: runs)
        let unreadHeaderKey = unreadHeaderKey()
        let sections = zip(runs, ids).map { run, id in
            makeSection(id: id, items: items[run.range], unreadHeaderKey: unreadHeaderKey)
        }
        let positions = items.enumerated().map { ($0.element.clientKey, $0.offset) }
        return MessagesFeed(
            sections: sections,
            positions: Dictionary(positions, uniquingKeysWith: { first, _ in first }),
            newestServerMessageId: serverMessages.first?.messageId
        )
    }

    /// Сообщение, над которым стоит заголовок непрочитанных: самое старое серверное сообщение после границы от другого
    /// отправителя. Если ни одного сообщения до границы в окне нет, а есть более старые, заголовок выше окна —
    /// он появится при подгрузке.
    /// - Returns: `nil` — заголовка в окне нет.
    private func unreadHeaderKey() -> MessageClientKey? {
        guard let unreadBoundary else { return nil }
        guard !hasOlder || serverMessages.contains(where: { $0.messageId <= unreadBoundary }) else { return nil }
        let currentUserId = context.currentUserId
        return serverMessages.last { $0.messageId > unreadBoundary && $0.senderId != currentUserId }?.clientKey
    }

    /// Разбивает элементы на подряд идущие серии одного дня.
    /// - Parameter items: элементы ленты, сначала самые новые.
    private func dayRuns(of items: [ChatFeedItem]) -> [DayRun] {
        var runs: [DayRun] = []
        for (index, item) in items.enumerated() {
            let day = context.calendar.startOfDay(for: item.createdAt)
            guard let last = runs.last, last.day == day else {
                runs.append(DayRun(day: day, range: index..<index + 1))
                continue
            }
            runs[runs.count - 1] = DayRun(day: day, range: last.range.lowerBound..<index + 1)
        }
        return runs
    }

    /// Идентификаторы секций. Номер серии дня считается от самых старых: подгрузка старых сообщений дописывает
    /// их в конец и не меняет `id` уже показанных секций.
    /// - Parameter runs: серии дней, сначала самые новые.
    private func sectionIDs(of runs: [DayRun]) -> [MessageDaySectionID] {
        var occurrences: [Date: Int] = [:]
        let oldestFirst = runs.reversed().map { run in
            let occurrence = occurrences[run.day, default: 0]
            occurrences[run.day] = occurrence + 1
            return MessageDaySectionID(day: run.day, occurrence: occurrence)
        }
        return oldestFirst.reversed()
    }

    /// Собирает секцию: заголовок дня и сообщения. Серия отправителя прерывается на границе секции — её самое
    /// старое сообщение всегда показывается с аватаром и именем.
    /// - Parameters:
    ///   - id: идентификатор секции.
    ///   - items: элементы секции, сначала самые новые.
    ///   - unreadHeaderKey: сообщение, над которым стоит заголовок непрочитанных; в секцию попадает, если оно в ней.
    private func makeSection(
        id: MessageDaySectionID,
        items: ArraySlice<ChatFeedItem>,
        unreadHeaderKey: MessageClientKey?
    ) -> MessageDaySectionDisplayModel {
        let messages = items.indices.map { index in
            let item = items[index]
            // Порядок — от новых к старым, поэтому первое сообщение серии — то, за которым идёт сообщение
            // другого отправителя или конец секции.
            let isFirstInSeries = index + 1 == items.endIndex || items[index + 1].senderId != item.senderId
            let sender = isFirstInSeries ? senders[item.senderId] : nil
            switch item {
            case let .sent(message):
                return MessageDisplayModel(message: message, sender: sender, context: context)
            case let .outgoing(outgoing):
                return MessageDisplayModel(outgoing: outgoing, sender: sender, context: context)
            }
        }
        let title = context.dateHeaderFormatter.string(from: items[items.startIndex].createdAt, now: context.now)
        let header = unreadHeaderKey.flatMap { key in items.contains { $0.clientKey == key } ? key : nil }
        return MessageDaySectionDisplayModel(id: id, title: title, messages: messages, unreadHeaderBefore: header)
    }
}

/// Собранная лента: секции и позиции сообщений.
struct MessagesFeed: Sendable {
    /// Секции по дням, сначала самые новые.
    let sections: [MessageDaySectionDisplayModel]
    /// Позиция каждого сообщения в плоском порядке ленты, от самого нового.
    let positions: [MessageClientKey: Int]
    /// Самое новое серверное сообщение ленты — для правила прочтения; `nil` — серверных сообщений нет.
    let newestServerMessageId: Int?
}

/// Подряд идущие элементы ленты одного дня.
private struct DayRun {
    /// Начало дня в календаре устройства.
    let day: Date
    /// Индексы элементов в ленте.
    let range: Range<Int>
}

/// Элемент ленты: сообщение с сервера или неотправленное сообщение текущего пользователя.
private enum ChatFeedItem {
    case sent(Message)
    case outgoing(OutgoingMessage)

    var senderId: Int {
        switch self {
        case let .sent(message): return message.senderId
        case let .outgoing(message): return message.senderId
        }
    }

    /// Ключ сообщения — тот же, что `id` в `MessageDisplayModel`.
    var clientKey: MessageClientKey {
        switch self {
        case let .sent(message): return message.clientKey
        case let .outgoing(message): return message.clientKey
        }
    }

    /// Время, по которому сообщение попадает в день: у серверного — время сервера, у неотправленного — момент
    /// нажатия «Отправить».
    var createdAt: Date {
        switch self {
        case let .sent(message): return message.createdAt.date
        case let .outgoing(message): return message.createdAt
        }
    }
}

/// Цикл обновления ленты одного вызова `observeMessages()`: сигналы изменений, пауза между обновлениями
/// и регистрация Observation.
@MainActor
private final class MessagesUpdateLoop {
    let changes: AsyncStream<Void>
    let signal: AsyncStream<Void>.Continuation
    /// Регистрация Observation поставлена и ещё не сработала. Под замком: `onChange` вызывается в потоке,
    /// где изменилось свойство.
    let isTracking = OSAllocatedUnfairLock(initialState: false)
    /// Идущая пауза между обновлениями; срочное изменение её прерывает.
    private var throttleWait: Task<Void, Never>?
    /// Пришло срочное изменение: следующее обновление — без паузы.
    private var isUrgentUpdatePending = false

    init() {
        (changes, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// Начало обновления: срочность учтена.
    func beginUpdate() {
        isUrgentUpdatePending = false
    }

    /// Отмечает, что регистрация Observation ставится.
    /// - Returns: `false` — прежняя регистрация ещё не сработала, новая не нужна.
    func armTracking() -> Bool {
        isTracking.withLock { isTracking in
            guard !isTracking else { return false }
            isTracking = true
            return true
        }
    }

    /// Изменение, которое подождёт паузы между обновлениями.
    func signalChange() {
        signal.yield()
    }

    /// Изменение, которое нужно показать сразу: прерывает паузу.
    func signalUrgentChange() {
        isUrgentUpdatePending = true
        throttleWait?.cancel()
        signal.yield()
    }

    /// Пауза между обновлениями ленты; пропускается, если уже пришло срочное изменение.
    /// - Parameter sleep: ожидание.
    func waitBeforeNextUpdate(sleep: @escaping ChatViewModel.Sleep) async {
        guard !isUrgentUpdatePending else { return }
        let wait = Task { _ = try? await sleep(ChatViewModel.messagesUpdateInterval) }
        throttleWait = wait
        await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            wait.cancel()
        }
        throttleWait = nil
    }
}
