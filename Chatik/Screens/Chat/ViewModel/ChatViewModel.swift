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
/// Тексты и производные данные — в `ChatViewModel+Texts`.
@MainActor
@Observable
final class ChatViewModel {
    /// Текст в поле ввода. Каждое изменение меняет черновик в памяти.
    var messageText = "" {
        didSet { updateDraft() }
    }
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?
    /// `clientId` неотправленного сообщения, для которого показан выбор «повторить / удалить». `nil` — выбор скрыт.
    var failedMessageActionsClientId: String?
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
    let now: () -> Date
    private let draftService: MessageDraftServiceProtocol
    /// Пользователь, открывший экран, — владелец черновика; `nil` — сессии нет, черновик не меняется.
    /// Задаётся в конце `init`, после подстановки черновика: подстановка не возвращается в сервис через `didSet`.
    @ObservationIgnored private var draftUserId: Int?
    /// Календарь, по которому лента делится на дни. Функция, а не значение: после смены часового пояса
    /// `Calendar.current` уже другой.
    private let calendar: () -> Calendar
    private let messagesList: MessagesListServiceProtocol
    private let dateHeaderFormatterProvider: MessageDateHeaderFormatterProviding
    private let timeChangeService: SignificantTimeChangeServiceProtocol
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

    /// Ожидание между обновлениями ленты; подменяется в тестах.
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// - Parameters:
    ///   - conversation: открытая переписка.
    ///   - messagesList: лента переписки.
    ///   - messageSendQueue: очередь отправки сообщений.
    ///   - sessionService: сессия — по ней сообщения делятся на исходящие и входящие; её пользователь — владелец
    ///     черновика.
    ///   - draftService: черновики — текст поля ввода между открытиями экрана.
    ///   - userCache: кэш пользователей — имена собеседника и отправителей.
    ///   - localizationService: язык форматирования времени и заголовков дней.
    ///   - messageTextValidator: проверка текста перед отправкой.
    ///   - dateHeaderFormatterProvider: форматтеры заголовков дней по языку.
    ///   - timeChangeService: полночь, смена часового пояса и перевод часов — пересобирают заголовки.
    ///   - now: текущее время; подменяется в тестах форматирования.
    ///   - calendar: календарь устройства; подменяется в тестах, чтобы деление на дни не зависело от устройства.
    ///   - sleep: ожидание между обновлениями ленты; подменяется в тестах.
    init(
        conversation: Conversation,
        messagesList: MessagesListServiceProtocol,
        messageSendQueue: MessageSendQueueProtocol,
        sessionService: SessionServiceProtocol,
        draftService: MessageDraftServiceProtocol,
        userCache: UserCacheServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        messageTextValidator: MessageTextValidatorProtocol,
        dateHeaderFormatterProvider: MessageDateHeaderFormatterProviding,
        timeChangeService: SignificantTimeChangeServiceProtocol,
        now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { .current },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.conversation = conversation
        self.messagesList = messagesList
        self.messageSendQueue = messageSendQueue
        self.sessionService = sessionService
        self.draftService = draftService
        self.userCache = userCache
        self.localizationService = localizationService
        self.messageTextValidator = messageTextValidator
        self.dateHeaderFormatterProvider = dateHeaderFormatterProvider
        self.timeChangeService = timeChangeService
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
        // Только чтение: SwiftUI может создать ViewModel несколько раз и оставить первый экземпляр.
        messageText = draftService.draft(for: conversation.conversationId) ?? ""
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
            messagePositions = feed.positions
            if feed.sections != sections {
                sections = feed.sections
            }
            isLoaded = isWindowLoaded
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
            errorMessage = ErrorMessages.message(for: failure)
        }
        serverMessages = snapshot.messages
        isServerWindowLoaded = snapshot.isLoaded
        if snapshot.isUrgent {
            requestImmediateUpdate()
        } else {
            updateLoops.forEach { $0.signalChange() }
        }
    }

    /// Обновляет ленту сразу, прерывая паузу между обновлениями.
    private func requestImmediateUpdate() {
        updateLoops.forEach { $0.signalUrgentChange() }
    }

    /// Синхронизация по pull-to-refresh: ждёт её окончания, ошибка придёт в снимке.
    func refresh() async {
        await messagesList.synchronize()
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

    /// Обработчик кнопки отправки: ставит сообщение в очередь и сразу очищает поле. Сообщение появляется внизу
    /// ленты в статусе «отправляется» — без паузы обновления.
    func didTapSend() {
        guard isSendEnabled else { return }
        messageSendQueue.enqueue(text: messageText, conversationId: conversation.conversationId)
        messageText = ""
        if let draftUserId {
            draftService.remove(conversationId: conversation.conversationId, userId: draftUserId)
        }
        requestImmediateUpdate()
    }

    // MARK: - Черновик

    /// Записывает черновик в БД — точка сохранения: уход с экрана, уход приложения в неактивное состояние или в фон.
    /// Повторное сохранение без изменений в БД не пишет.
    func saveDraft() {
        guard let draftUserId else { return }
        draftService.save(text: messageText, conversationId: conversation.conversationId, userId: draftUserId)
    }

    /// Меняет черновик в памяти после изменения поля ввода.
    private func updateDraft() {
        guard let draftUserId else { return }
        draftService.update(text: messageText, conversationId: conversation.conversationId, userId: draftUserId)
    }

    /// Обработчик тапа по сообщению: для неотправленного показывает выбор «повторить / удалить».
    /// - Parameter message: сообщение, по которому тапнули.
    func didTapMessage(_ message: MessageDisplayModel) {
        guard message.deliveryState == .failed else { return }
        failedMessageActionsClientId = message.id.clientId
    }

    /// Повторяет отправку неотправленного сообщения.
    /// - Parameter clientId: идентификатор сообщения.
    func retrySending(clientId: String) {
        messageSendQueue.retry(clientId: clientId)
    }

    /// Удаляет неотправленное сообщение.
    /// - Parameter clientId: идентификатор сообщения.
    func deleteOutgoing(clientId: String) {
        messageSendQueue.delete(clientId: clientId)
    }
}

/// Всё, из чего собирается лента, — значениями, чтобы сборка шла вне main.
struct MessagesBuildInput: Sendable {
    /// Сообщения с сервера, сначала самые новые.
    let serverMessages: [Message]
    /// Неотправленные сообщения переписки, сначала самые старые.
    let outgoing: [OutgoingMessage]
    /// Отправители по идентификатору.
    let senders: [Int: CachedUser]
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
        let sections = zip(runs, ids).map { run, id in makeSection(id: id, items: items[run.range]) }
        let positions = items.enumerated().map { ($0.element.clientKey, $0.offset) }
        return MessagesFeed(sections: sections, positions: Dictionary(positions, uniquingKeysWith: { first, _ in first }))
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
    private func makeSection(id: MessageDaySectionID, items: ArraySlice<ChatFeedItem>) -> MessageDaySectionDisplayModel {
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
        return MessageDaySectionDisplayModel(id: id, title: title, messages: messages)
    }
}

/// Собранная лента: секции и позиции сообщений.
struct MessagesFeed: Sendable {
    /// Секции по дням, сначала самые новые.
    let sections: [MessageDaySectionDisplayModel]
    /// Позиция каждого сообщения в плоском порядке ленты, от самого нового.
    let positions: [MessageClientKey: Int]
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
