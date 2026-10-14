//
//  ConversationListService.swift
//  Chatik
//

import Foundation
import os

/// Подъём переписки по ответу `/messages/send` — узкий протокол для очереди отправки.
@MainActor
protocol ConversationPositionUpdating: AnyObject {
    /// Поднимает переписку по сообщению, которое создал сервер в ответ на отправку.
    func applySentMessage(_ message: Message)
}

@MainActor
protocol ConversationListServiceProtocol: ConversationPositionUpdating, AuthServiceObserver {
    /// Переписки по позиции: `positionUpdatedAt` ↓, `conversationId` ↓.
    var conversations: [Conversation] { get }
    /// Идёт ли стартовая синхронизация — для индикатора «Обновление…».
    var isSyncing: Bool { get }
    /// Идёт ли загрузка следующей страницы.
    var isLoadingNextPage: Bool { get }
    /// Есть ли на сервере переписки после загруженных.
    var hasMorePages: Bool { get }
    /// Получена ли с сервера хотя бы первая страница списка — до этого пустой список ещё не значит «чатов нет».
    var isLoaded: Bool { get }

    /// Подписывается на очередь событий и запускает чтение кэша из БД. Вызывается до `realtimeService.start()`.
    func start()
    /// Стартовая синхронизация; прерывает идущую (включая фоновую сверку информации).
    func synchronize()
    /// Синхронизация при открытии экрана: дожидается чтения кэша и запускает синхронизацию, если в этой сессии её
    /// ещё не было, — список не должен зависеть от того, подключится ли WebSocket. Ошибка пробрасывается;
    /// прерванная новой синхронизацией — завершается `CancellationError`.
    func synchronizeIfNeeded() async throws
    /// Pull-to-refresh: полная перезагрузка первой страницы без фильтра. Прерванная новой синхронизацией —
    /// завершается `CancellationError`.
    func refresh() async throws
    /// Начинает загрузку следующей страницы, если показана одна из последних переписок.
    func loadNextPageIfNeeded(currentConversationId: Int)
    /// Применяет полную версию переписки из REST (`createSingle`).
    func apply(_ conversation: Conversation)
}

/// Список переписок уровня приложения: хранит упорядоченный список дольше любого экрана и публикует его через
/// Observation. Единственный хранит список, единственный пишет переписки в БД и единственный применяет правила
/// слияния (`ConversationMerger`).
///
/// **Инвариант префикса.** Список в памяти совпадает с переписками в БД и остаётся непрерывным началом серверного
/// списка (с точностью до переписок, пропавших с сервера, — их убирает только pull-to-refresh). Переписка из события
/// с новой позицией всегда попадает в префикс; переписка из сверки информации, которой нет локально, отбрасывается.
///
/// **Синхронизация** запускается событием `connected`, а если его в сессии ещё не было — открытием экрана списка
/// (`synchronizeIfNeeded()`), чтобы список не зависел от WebSocket: кэш показан сразу, затем дельта позиций
/// (`positionUpdatedAfter`) под арендой очереди событий; при переполнении дельты хвост инвалидируется, иначе
/// без аренды идёт сверка информации (`updatedInfoAfter`). Водяные знаки хранятся в БД (`ConversationListState`).
///
/// **Сдвиг следующей страницы** (`serverLoadedCount`) считается с недобором: повторы безопасны — их уберёт слияние,
/// пропуск — нет.
@MainActor
@Observable
final class ConversationListService: ConversationListServiceProtocol {
    /// Размер страницы списка.
    static let pageSize = 30
    /// Размер страницы сверки информации.
    static let infoPageSize = 100
    /// Запас фильтров синхронизации: время на сервере фиксируется до коммита транзакции, и переписка с чуть меньшим
    /// временем может стать видна чуть позже. Лишние переписки в ответе безвредны — слияние идемпотентно.
    static let syncMargin: Int64 = 5000
    /// За сколько переписок до конца списка начинается загрузка следующей страницы.
    static let prefetchThreshold = 5

    private(set) var conversations: [Conversation] = []
    private(set) var isSyncing = false
    private(set) var isLoadingNextPage = false

    var hasMorePages: Bool {
        listState.hasMorePages
    }

    var isLoaded: Bool {
        listState.isLoaded
    }

    private let conversationService: ConversationServiceProtocol
    private let storage: ConversationStorageServiceProtocol
    private let eventQueue: RealtimeEventQueueProtocol
    private let userCache: UserCacheServiceProtocol

    /// Индекс переписки в `conversations` по `conversationId`.
    private var indexById: [Int: Int] = [:]
    private var serverLoadedCount = 0
    private var listState = ConversationListState()
    /// Изменения из `applySentMessage` и `apply(_:)`, пришедшие, пока идёт основная фаза синхронизации:
    /// после замены списка страницей они сливаются с ней заново. `nil` — основная фаза не идёт.
    private var pendingLocalUpdates: [ConversationUpdate]?
    private var cacheTask: Task<Void, Never>?
    /// Прочитан ли кэш (или чтение не удалось): до этого `listState` — значение по умолчанию, и писать его в БД
    /// нельзя — оно затёрло бы сохранённые водяные знаки.
    private var isCacheLoaded = false
    /// Запускалась ли в этой сессии синхронизация или `refresh()` — `synchronizeIfNeeded()` тогда не нужен.
    private var didStartSync = false
    /// Переписка, показ которой не запустил загрузку следующей страницы из-за основной фазы синхронизации:
    /// после фазы проверка повторяется — строка уже на экране, и `onAppear` для неё не придёт.
    private var deferredPrefetchId: Int?
    private var subscription: RealtimeSubscription?
    /// Поколение синхронизации: новая синхронизация, `refresh()` и выход его меняют, и ответы прежних отбрасываются,
    /// даже если запрос не успел отмениться.
    private var syncGeneration = 0
    /// Поколение сессии: меняется только выходом из аккаунта — записи и ответы, начатые до него, не применяются.
    private var sessionGeneration = 0
    /// Основная фаза синхронизации или `refresh()`.
    private var mainTask: Task<Void, Error>?
    private var infoSyncTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    /// Загрузки переписок, отсутствующих в списке, по ответу на отправку.
    private var lookupTasks: [UUID: Task<Void, Never>] = [:]
    /// Последняя запись в БД: следующая начинается только после неё — записи идут в порядке изменений в памяти.
    private var lastWrite: Task<Void, Never>?

    /// - Parameters:
    ///   - conversationService: источник `/conversations/*`.
    ///   - storage: кэш списка и состояние синхронизации в БД.
    ///   - eventQueue: очередь событий WebSocket; на время основной фазы синхронизации обработка приостанавливается.
    ///   - userCache: кэш пользователей — собеседники переписок из БД.
    init(
        conversationService: ConversationServiceProtocol,
        storage: ConversationStorageServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        userCache: UserCacheServiceProtocol
    ) {
        self.conversationService = conversationService
        self.storage = storage
        self.eventQueue = eventQueue
        self.userCache = userCache
    }

    // MARK: - Старт

    /// Подписывается на очередь событий и запускает чтение кэша. Повторный вызов ничего не делает.
    func start() {
        guard cacheTask == nil else { return }
        subscription = eventQueue.subscribe { [weak self] event in
            await self?.handle(event)
        }
        let session = sessionGeneration
        cacheTask = Task { await loadCache(session: session) }
    }

    /// Читает список и состояние синхронизации из БД. Изменения, применённые до окончания чтения (например,
    /// `apply(_:)`), сливаются поверх кэша. Ошибка чтения не мешает работе — список дождётся синхронизации.
    /// - Parameter session: поколение сессии на момент запуска.
    private func loadCache(session: Int) async {
        let stored: (conversations: [Conversation], state: ConversationListState)
        do {
            stored = try await storage.fetchList()
        } catch {
            Logger.storage.error("Не удалось прочитать список переписок из БД: \(String(describing: error), privacy: .public)")
            isCacheLoaded = true
            return
        }
        isCacheLoaded = true
        guard session == sessionGeneration else { return }
        let applied = conversations
        setConversations(stored.conversations)
        upsert(applied.map(ConversationUpdate.full), insertIfMissing: true)
        listState = stored.state
        serverLoadedCount = stored.conversations.count
        let opponentIds = stored.conversations.compactMap(\.opponentUserId)
        Task { await userCache.loadUsers(ids: opponentIds) }
    }

    // MARK: - События

    /// Обрабатывает событие очереди. `connected` берёт аренду синхронно, до первого `await`: все события после него
    /// накопятся и применятся после ответа синхронизации. Остальные события ждут чтения кэша.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) async {
        guard event != .connected else {
            synchronize()
            return
        }
        await cacheTask?.value
        switch event {
        case .connected:
            break
        case let .conversationCreated(conversation):
            applyCreated(conversation)
        case let .messageReceived(message, lastMessage):
            await applyReceived(ConversationPatch(message: message, lastMessage: lastMessage))
        case let .messageEdited(message, lastMessage):
            guard let lastMessage else { return }
            persist(upsert(.patch(ConversationPatch(message: message, lastMessage: lastMessage)), insertIfMissing: false))
        }
    }

    /// Применяет событие `singleCreated`: переписка сливается или встаёт по сортировке. Водяной знак позиции
    /// поднимается, информации — нет: смену названия и аватара WebSocket не присылает, её находит только сверка,
    /// и подъём от события пропустил бы правки, сделанные раньше.
    /// - Parameter conversation: созданная переписка.
    private func applyCreated(_ conversation: Conversation) {
        let changed = upsert(.full(conversation), insertIfMissing: true)
        raisePositionWatermark(to: conversation.positionUpdatedAt)
        persist(changed)
    }

    /// Применяет событие `received`. Переписки нет в списке — она загружается через `getBatch`; обработчик ждёт ответ,
    /// и все следующие события копятся в очереди. При ошибке водяной знак ограничивается потолком, а синхронизация
    /// планируется заново: вернуть переписку может только дельта позиций.
    /// - Parameter patch: позиция и превью из события.
    private func applyReceived(_ patch: ConversationPatch) async {
        guard indexById[patch.conversationId] == nil else {
            let changed = upsert(.patch(patch), insertIfMissing: false)
            raisePositionWatermark(to: patch.positionUpdatedAt)
            persist(changed)
            return
        }
        let session = sessionGeneration
        do {
            let batch = try await conversationService.fetchConversations(ids: [patch.conversationId])
            guard session == sessionGeneration else { return }
            let inserted = insertFetched(batch, patch: patch)
            raisePositionWatermark(to: patch.positionUpdatedAt)
            persist(inserted)
        } catch {
            guard session == sessionGeneration, !Task.isCancelled else { return }
            Logger.conversationList.error("getBatch по событию не удался: \(String(describing: error), privacy: .public)")
            lowerPositionWatermarkCeiling(to: patch.positionUpdatedAt)
            persist(nil)
            synchronize()
        }
    }

    /// Вставляет переписку из ответа `getBatch` и сливает с ней патч. Переписки нет на сервере — ничего не делает.
    /// - Parameters:
    ///   - batch: ответ `getBatch`.
    ///   - patch: позиция и превью, по которым переписку загружали.
    /// - Returns: вставленная переписка; `nil` — её нет на сервере.
    private func insertFetched(_ batch: ConversationsBatch, patch: ConversationPatch) -> Conversation? {
        guard let fetched = batch.conversations.first(where: { $0.conversationId == patch.conversationId }) else { return nil }
        upsert(.full(fetched), insertIfMissing: true)
        upsert(.patch(patch), insertIfMissing: false)
        return indexById[patch.conversationId].map { conversations[$0] }
    }

    // MARK: - Изменения из REST

    /// Поднимает переписку по ответу `/messages/send`, не дожидаясь события. Позднее событие `received` с тем же
    /// сообщением сливается вхолостую. Водяной знак не двигается: при оборванном WebSocket это скрыло бы от дельты
    /// переписки, поднявшиеся раньше. Переписки нет в списке — она загружается через `getBatch`.
    /// - Parameter message: сообщение, созданное сервером.
    func applySentMessage(_ message: Message) {
        let patch = ConversationPatch(message: message)
        guard indexById[patch.conversationId] == nil else {
            applyLocal(.patch(patch))
            return
        }
        lookUpSentConversation(patch)
    }

    /// Применяет полную версию переписки из REST (`createSingle`). Водяные знаки не двигаются.
    /// - Parameter conversation: переписка.
    func apply(_ conversation: Conversation) {
        applyLocal(.full(conversation))
    }

    /// Применяет изменение, пришедшее мимо очереди событий, и запоминает его на время основной фазы синхронизации —
    /// чтобы замена списка страницей его не стёрла.
    /// - Parameter update: пришедшая версия.
    private func applyLocal(_ update: ConversationUpdate) {
        pendingLocalUpdates?.append(update)
        persist(upsert(update, insertIfMissing: true))
    }

    /// Загружает переписку, которой нет в списке, по ответу на отправку и вставляет её. Ошибка не страшна:
    /// переписку вставит событие `received` по тому же сообщению или синхронизация.
    /// - Parameter patch: позиция и превью из ответа на отправку.
    private func lookUpSentConversation(_ patch: ConversationPatch) {
        let id = UUID()
        let session = sessionGeneration
        lookupTasks[id] = Task {
            defer { lookupTasks[id] = nil }
            guard let batch = try? await conversationService.fetchConversations(ids: [patch.conversationId]),
                  session == sessionGeneration,
                  let fetched = batch.conversations.first(where: { $0.conversationId == patch.conversationId }) else { return }
            applyLocal(.full(fetched))
            applyLocal(.patch(patch))
        }
    }

    // MARK: - Синхронизация

    /// Стартовая синхронизация. Аренда очереди берётся синхронно — ещё в обработчике `connected`; снимается, когда
    /// основная фаза закончится (ответом, ошибкой или отменой).
    func synchronize() {
        startSynchronization()
    }

    /// Синхронизация при открытии экрана: сначала дожидается кэша — иначе без водяных знаков вместо дельты
    /// ушла бы полная загрузка. Если синхронизация в сессии уже была (по `connected` или pull-to-refresh),
    /// ничего не делает.
    func synchronizeIfNeeded() async throws {
        await cacheTask?.value
        guard !didStartSync else { return }
        let (task, generation) = startSynchronization()
        do {
            try await task.value
        } catch {
            guard isCurrent(generation) else { throw CancellationError() }
            throw error
        }
    }

    /// Запускает основную фазу синхронизации. Ошибка логируется и пробрасывается из задачи.
    /// - Returns: задача основной фазы и её поколение.
    @discardableResult
    private func startSynchronization() -> (task: Task<Void, Error>, generation: Int) {
        let lease = eventQueue.suspendProcessing(reason: "conversationList.sync")
        let generation = beginMainPhase(showsIndicator: true)
        let task = Task {
            defer { lease.release() }
            defer { finishMainPhase(generation: generation) }
            await cacheTask?.value
            do {
                try await runMainPhase(generation: generation, lease: lease)
            } catch {
                logSyncFailure(error, generation: generation)
                throw error
            }
        }
        mainTask = task
        return (task, generation)
    }

    /// Pull-to-refresh: та же полная загрузка, что и при первой синхронизации, с арендой и новым поколением.
    /// Единственный способ убрать из кэша переписку, пропавшую с сервера. Загрузка идёт в отдельной задаче:
    /// отмена вызывающей задачи (SwiftUI отменяет `.refreshable`) её не прерывает.
    func refresh() async throws {
        let generation = beginMainPhase(showsIndicator: false)
        let task = Task {
            try await eventQueue.withProcessingSuspended(reason: "conversationList.refresh") { lease in
                await cacheTask?.value
                try await loadFirstPage(generation: generation, lease: lease)
            }
        }
        mainTask = task
        defer { finishMainPhase(generation: generation) }
        do {
            try await task.value
        } catch {
            guard isCurrent(generation) else { throw CancellationError() }
            throw error
        }
    }

    /// Начинает основную фазу: прерывает идущие синхронизацию, сверку и загрузку страницы, меняет поколение
    /// и начинает копить изменения мимо очереди.
    /// - Parameter showsIndicator: показывать ли индикатор «Обновление…» (pull-to-refresh показывает свой).
    /// - Returns: поколение новой фазы.
    private func beginMainPhase(showsIndicator: Bool) -> Int {
        mainTask?.cancel()
        infoSyncTask?.cancel()
        nextPageTask?.cancel()
        infoSyncTask = nil
        nextPageTask = nil
        isLoadingNextPage = false
        syncGeneration += 1
        isSyncing = showsIndicator
        pendingLocalUpdates = []
        didStartSync = true
        return syncGeneration
    }

    /// Заканчивает основную фазу, если она ещё текущая, и повторяет отложенную на время фазы проверку
    /// следующей страницы.
    /// - Parameter generation: поколение фазы.
    private func finishMainPhase(generation: Int) {
        guard isCurrent(generation) else { return }
        isSyncing = false
        pendingLocalUpdates = nil
        guard let deferredPrefetchId else { return }
        self.deferredPrefetchId = nil
        loadNextPageIfNeeded(currentConversationId: deferredPrefetchId)
    }

    /// Основная фаза синхронизации: полная загрузка, если дельту запросить не от чего, иначе дельта позиций.
    /// - Parameters:
    ///   - generation: поколение фазы.
    ///   - lease: аренда очереди событий.
    private func runMainPhase(generation: Int, lease: RealtimeQueueLease) async throws {
        guard listState.isLoaded, let watermark = listState.positionWatermark else {
            try await loadFirstPage(generation: generation, lease: lease)
            return
        }
        try await loadPositionDelta(from: watermark, generation: generation, lease: lease)
    }

    /// Полная загрузка: первая страница без фильтра заменяет список и БД.
    /// - Parameters:
    ///   - generation: поколение фазы.
    ///   - lease: аренда очереди событий.
    private func loadFirstPage(generation: Int, lease: RealtimeQueueLease) async throws {
        let page = try await conversationService.fetchConversations(filter: .none(offset: nil), count: Self.pageSize)
        try ensureCurrent(generation)
        guard !lease.isExpired else {
            mergeAfterExpiredLease(page)
            return
        }
        replaceList(with: page)
    }

    /// Дельта позиций от водяного знака с запасом. Поднялось больше страницы — хвост инвалидируется: страница с
    /// фильтром совпадает с началом полного списка. Иначе дельта сливается, и запускается сверка информации.
    /// - Parameters:
    ///   - watermark: водяной знак позиции.
    ///   - generation: поколение фазы.
    ///   - lease: аренда очереди событий.
    private func loadPositionDelta(from watermark: ServerTime, generation: Int, lease: RealtimeQueueLease) async throws {
        let infoFrom = listState.infoWatermark
        let page = try await conversationService.fetchConversations(
            filter: .positionUpdatedAfter(watermark.adding(milliseconds: -Self.syncMargin), offset: nil),
            count: Self.pageSize
        )
        try ensureCurrent(generation)
        guard !lease.isExpired else {
            mergeAfterExpiredLease(page)
            return
        }
        guard !page.hasNext else {
            replaceList(with: page)
            return
        }
        listState.positionWatermarkCeiling = nil
        let changed = upsert(page.conversations.map(ConversationUpdate.full), insertIfMissing: true)
        page.conversations.map(\.positionUpdatedAt).max().map(raisePositionWatermark(to:))
        persist(changed)
        startInfoSync(from: infoFrom, generation: generation)
    }

    /// Заменяет список и БД первой страницей (полная загрузка или инвалидация хвоста), снимает потолок водяного
    /// знака и ставит водяные знаки по максимумам страницы. Изменения мимо очереди, пришедшие за время запроса,
    /// сливаются со страницей заново.
    /// - Parameter page: первая страница списка — без фильтра или с `positionUpdatedAfter`.
    private func replaceList(with page: ConversationsPage) {
        setConversations(page.conversations.sorted { $0.isOrderedBefore($1) })
        upsert(pendingLocalUpdates ?? [], insertIfMissing: true)
        serverLoadedCount = page.conversations.count
        listState = ConversationListState(
            isLoaded: true,
            hasMorePages: page.hasNext,
            positionWatermark: page.conversations.map(\.positionUpdatedAt).max(),
            positionWatermarkCeiling: nil,
            infoWatermark: page.conversations.map(\.updatedInfoAt).max()
        )
        persistReplacement()
    }

    /// Применяет страницу, полученную под арендой, которую сняли принудительно: очередь уже применила более новые
    /// события, поэтому страница только сливается. Водяные знаки не двигаются — следующая синхронизация повторит
    /// запрос и закроет возможный разрыв.
    /// - Parameter page: первая страница или дельта позиций.
    private func mergeAfterExpiredLease(_ page: ConversationsPage) {
        Logger.conversationList.fault("Ответ синхронизации пришёл после принудительного снятия аренды")
        let changed = upsert(page.conversations.map(ConversationUpdate.full), insertIfMissing: true)
        if !listState.isLoaded {
            listState.isLoaded = true
            listState.hasMorePages = page.hasNext
            serverLoadedCount = page.conversations.count
        }
        persist(changed)
    }

    /// Логирует ошибку основной фазы текущего поколения. Кэш остаётся на экране, повтор — при следующем
    /// `connected` или pull-to-refresh.
    /// - Parameters:
    ///   - error: ошибка запроса.
    ///   - generation: поколение фазы.
    private func logSyncFailure(_ error: Error, generation: Int) {
        guard isCurrent(generation) else { return }
        Logger.conversationList.error("Синхронизация списка не удалась: \(String(describing: error), privacy: .public)")
    }

    // MARK: - Сверка информации

    /// Запускает фоновую сверку информации — без аренды и без индикатора.
    /// - Parameters:
    ///   - start: водяной знак информации на момент начала синхронизации; `nil` — сверять не от чего.
    ///   - generation: поколение синхронизации.
    private func startInfoSync(from start: ServerTime?, generation: Int) {
        guard let start else { return }
        infoSyncTask = Task { await runInfoSync(from: start, generation: generation) }
    }

    /// Сверяет информацию постранично курсором `(updatedInfoAt, conversationId)`. Новая синхронизация прерывает
    /// цикл; ошибка сети просто останавливает его — продолжит следующая синхронизация с сохранённого водяного знака.
    /// - Parameters:
    ///   - start: водяной знак информации.
    ///   - generation: поколение синхронизации.
    private func runInfoSync(from start: ServerTime, generation: Int) async {
        var filter = ConversationListFilter.updatedInfoAfter(start.adding(milliseconds: -Self.syncMargin), afterId: nil)
        while isCurrent(generation), !Task.isCancelled {
            guard let page = try? await conversationService.fetchConversations(filter: filter, count: Self.infoPageSize),
                  isCurrent(generation), !Task.isCancelled,
                  let last = applyInfoPage(page) else { return }
            guard page.hasNext else { return }
            filter = .updatedInfoAfter(last.updatedInfoAt, afterId: last.conversationId)
        }
    }

    /// Сливает страницу сверки с известными переписками (неизвестные отбрасываются — иначе в список попал бы чат
    /// с далёкой позиции) и двигает водяной знак информации: выдача идёт по возрастанию.
    /// - Parameter page: страница `updatedInfoAfter`.
    /// - Returns: последняя переписка страницы — курсор следующей; `nil` — страница пуста.
    private func applyInfoPage(_ page: ConversationsPage) -> Conversation? {
        let changed = upsert(page.conversations.map(ConversationUpdate.full), insertIfMissing: false)
        guard let last = page.conversations.last else { return nil }
        listState.infoWatermark = last.updatedInfoAt
        persist(changed)
        return last
    }

    // MARK: - Пагинация

    /// Начинает загрузку следующей страницы, если показана одна из последних переписок. Пока идёт основная фаза
    /// синхронизации, сдвиг нестабилен: проверка откладывается до конца фазы.
    /// - Parameter currentConversationId: переписка, которая появилась на экране.
    func loadNextPageIfNeeded(currentConversationId: Int) {
        guard pendingLocalUpdates == nil else {
            deferredPrefetchId = currentConversationId
            return
        }
        guard listState.isLoaded, listState.hasMorePages, nextPageTask == nil,
              let index = indexById[currentConversationId],
              index >= conversations.count - Self.prefetchThreshold else { return }
        let generation = syncGeneration
        isLoadingNextPage = true
        nextPageTask = Task { await loadNextPage(generation: generation) }
    }

    /// Загружает следующую страницу без фильтра: повторы сливаются, новые встают по сортировке. Водяные знаки
    /// страница не двигает. Ошибка логируется — загрузка повторится при прокрутке.
    /// - Parameter generation: поколение синхронизации на момент запуска.
    private func loadNextPage(generation: Int) async {
        defer {
            if isCurrent(generation) {
                isLoadingNextPage = false
                nextPageTask = nil
            }
        }
        let page: ConversationsPage
        do {
            page = try await conversationService.fetchConversations(filter: .none(offset: serverLoadedCount), count: Self.pageSize)
        } catch {
            // Отмену новой синхронизацией или выходом ошибкой не считаем.
            guard isCurrent(generation), !Task.isCancelled else { return }
            Logger.conversationList.error("Не удалось загрузить страницу списка: \(String(describing: error), privacy: .public)")
            return
        }
        guard isCurrent(generation) else { return }
        let changed = upsert(page.conversations.map(ConversationUpdate.full), insertIfMissing: true)
        serverLoadedCount += page.conversations.count
        listState.hasMorePages = page.hasNext
        persist(changed)
    }

    // MARK: - Выход из аккаунта

    /// Выход из аккаунта начинается (`AuthServiceObserver`): поколения меняются, все задачи отменяются и
    /// дожидаются вместе с записями в БД, список очищается. БД чистит `LocalStorageCleaner`.
    func authServiceWillLogout() async {
        sessionGeneration += 1
        syncGeneration += 1
        let tasks: [Task<Void, Never>?] = [infoSyncTask, nextPageTask] + lookupTasks.values.map { $0 }
        let mainTask = mainTask
        mainTask?.cancel()
        tasks.forEach { $0?.cancel() }
        _ = await mainTask?.result
        for task in tasks {
            await task?.value
        }
        await lastWrite?.value
        resetState()
    }

    /// Сбрасывает список и состояние синхронизации в памяти.
    private func resetState() {
        setConversations([])
        listState = ConversationListState()
        serverLoadedCount = 0
        isSyncing = false
        isLoadingNextPage = false
        pendingLocalUpdates = nil
        didStartSync = false
        deferredPrefetchId = nil
        mainTask = nil
        infoSyncTask = nil
        nextPageTask = nil
        lookupTasks = [:]
    }

    // MARK: - Водяные знаки

    /// Поднимает водяной знак позиции, не выше потолка. Пока водяного знака нет, его не от чего поднимать —
    /// следующая синхронизация будет полной загрузкой.
    /// - Parameter time: позиция из события или страницы синхронизации.
    private func raisePositionWatermark(to time: ServerTime) {
        guard let watermark = listState.positionWatermark else { return }
        let raised = max(watermark, time)
        listState.positionWatermark = listState.positionWatermarkCeiling.map { min(raised, $0) } ?? raised
    }

    /// Ставит потолок водяного знака позиции после неудачного `getBatch` и опускает под него сам водяной знак:
    /// пропущенную переписку вернёт только дельта позиций.
    /// - Parameter time: позиция пропущенной переписки.
    private func lowerPositionWatermarkCeiling(to time: ServerTime) {
        let ceiling = listState.positionWatermarkCeiling.map { min($0, time) } ?? time
        listState.positionWatermarkCeiling = ceiling
        listState.positionWatermark = listState.positionWatermark.map { min($0, ceiling) }
    }

    // MARK: - Список в памяти

    /// Сливает пришедшую версию с переписками списка: известная переписка сливается на месте и при смене позиции
    /// перемещается, неизвестная полная — вставляется по сортировке (если разрешено). Слияние без смены позиции
    /// (правка сообщения, информация) меняет один элемент, не копируя список и индекс, как это делает пачка.
    /// - Parameters:
    ///   - update: пришедшая версия.
    ///   - insertIfMissing: вставлять ли переписку, которой нет в списке.
    /// - Returns: изменённая переписка; `nil` — список не изменился.
    @discardableResult
    private func upsert(_ update: ConversationUpdate, insertIfMissing: Bool) -> Conversation? {
        guard let index = indexById[update.conversationId] else {
            return upsert([update], insertIfMissing: insertIfMissing).first
        }
        guard let result = ConversationMerger.merge(update, into: conversations[index]) else { return nil }
        guard result.isPositionChanged else {
            conversations[index] = result.conversation
            return result.conversation
        }
        var reordered = conversations
        reordered[index] = result.conversation
        reordered.sort { $0.isOrderedBefore($1) }
        setConversations(reordered)
        return result.conversation
    }

    /// Сливает пачку версий (страницу, накопленные локальные изменения) за один проход: известные переписки
    /// сливаются на месте, неизвестные полные дописываются в конец, затем список сортируется и индекс
    /// перестраивается один раз — а не на каждую переписку, как при поштучной вставке (O(k·n)). Наблюдатели
    /// получают одно изменение списка на всю пачку.
    /// - Parameters:
    ///   - updates: пришедшие версии; повторы одной переписки сливаются по порядку.
    ///   - insertIfMissing: вставлять ли переписки, которых нет в списке.
    /// - Returns: изменённые переписки в итоговых версиях, каждая один раз, в порядке первого изменения.
    @discardableResult
    private func upsert(_ updates: [ConversationUpdate], insertIfMissing: Bool) -> [Conversation] {
        var batch = MergeBatch(conversations: conversations, indexById: indexById)
        for update in updates {
            batch.apply(update, insertIfMissing: insertIfMissing)
        }
        guard !batch.changedIds.isEmpty else { return [] }
        if batch.needsSort {
            batch.conversations.sort { $0.isOrderedBefore($1) }
            setConversations(batch.conversations)
        } else {
            conversations = batch.conversations
            indexById = batch.indexById
        }
        return batch.changedIds.compactMap { id in indexById[id].map { conversations[$0] } }
    }

    /// Заменяет список целиком.
    /// - Parameter conversations: переписки в порядке списка.
    private func setConversations(_ conversations: [Conversation]) {
        self.conversations = conversations
        reindex()
    }

    /// Пересчитывает индекс по `conversationId`.
    private func reindex() {
        indexById = Dictionary(conversations.enumerated().map { ($1.conversationId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `true`, если поколение синхронизации всё ещё текущее.
    /// - Parameter generation: поколение на момент запуска.
    private func isCurrent(_ generation: Int) -> Bool {
        generation == syncGeneration
    }

    /// Бросает `CancellationError`, если поколение синхронизации сменилось.
    /// - Parameter generation: поколение на момент запуска.
    private func ensureCurrent(_ generation: Int) throws {
        guard isCurrent(generation) else { throw CancellationError() }
    }

    // MARK: - Локальная БД

    /// Ставит в цепочку запись изменённых переписок и состояния синхронизации. До чтения кэша пишутся только
    /// переписки: состояние в памяти ещё по умолчанию.
    /// - Parameter changed: изменённые переписки; пустой массив — пишется только состояние.
    private func persist(_ changed: [Conversation]) {
        let state = isCacheLoaded ? listState : nil
        guard state != nil || !changed.isEmpty else { return }
        write("сохранить переписки") { [storage] in
            try await storage.save(conversations: changed, state: state)
        }
    }

    /// Ставит в цепочку запись изменённой переписки и состояния синхронизации.
    /// - Parameter changed: изменённая переписка; `nil` — пишется только состояние.
    private func persist(_ changed: Conversation?) {
        persist(changed.map { [$0] } ?? [])
    }

    /// Ставит в цепочку замену списка в БД текущим списком.
    private func persistReplacement() {
        let conversations = conversations
        let state = listState
        write("заменить список переписок") { [storage] in
            try await storage.replaceList(with: conversations, state: state)
        }
    }

    /// Ставит запись в БД в конец цепочки. Запись, поставленная до выхода из аккаунта, не выполняется.
    /// Ошибка записи не мешает работе, но логируется.
    /// - Parameters:
    ///   - action: что делает запись — для лога.
    ///   - operation: запись.
    private func write(_ action: String, _ operation: @escaping () async throws -> Void) {
        let previous = lastWrite
        let session = sessionGeneration
        lastWrite = Task {
            await previous?.value
            guard session == sessionGeneration else { return }
            do {
                try await operation()
            } catch {
                Logger.storage.error("Список переписок: не удалось \(action, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension Logger {
    /// Лог списка переписок: сбои синхронизации не показываются пользователю — список повторит её сам.
    static let conversationList = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "ConversationList")
}

/// Пачка слияний над копией списка: изменения накапливаются, а сортировку и перестройку индекса делает
/// владелец один раз в конце.
private struct MergeBatch {
    var conversations: [Conversation]
    /// Индекс копии; верен для всех переписок, пока не понадобилась сортировка (`needsSort`).
    var indexById: [Int: Int]
    private(set) var changedIds: [Int] = []
    /// Порядок нарушен: сменилась позиция или переписка дописана в конец.
    private(set) var needsSort = false
    private var changedIdSet: Set<Int> = []

    init(conversations: [Conversation], indexById: [Int: Int]) {
        self.conversations = conversations
        self.indexById = indexById
    }

    /// Применяет одну версию: известная переписка сливается на месте, неизвестная полная дописывается в конец.
    /// - Parameters:
    ///   - update: пришедшая версия.
    ///   - insertIfMissing: дописывать ли переписку, которой нет в списке.
    mutating func apply(_ update: ConversationUpdate, insertIfMissing: Bool) {
        guard let index = indexById[update.conversationId] else {
            guard insertIfMissing, case let .full(conversation) = update else { return }
            indexById[conversation.conversationId] = conversations.count
            conversations.append(conversation)
            markChanged(conversation.conversationId, needsSort: true)
            return
        }
        guard let result = ConversationMerger.merge(update, into: conversations[index]) else { return }
        conversations[index] = result.conversation
        markChanged(update.conversationId, needsSort: result.isPositionChanged)
    }

    /// Запоминает изменённую переписку.
    /// - Parameters:
    ///   - id: `conversationId`.
    ///   - needsSort: нарушает ли изменение порядок списка.
    private mutating func markChanged(_ id: Int, needsSort: Bool) {
        self.needsSort = self.needsSort || needsSort
        guard changedIdSet.insert(id).inserted else { return }
        changedIds.append(id)
    }
}
