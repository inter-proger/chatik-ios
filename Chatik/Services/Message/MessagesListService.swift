//
//  MessagesListService.swift
//  Chatik
//

import Foundation
import os

protocol MessagesListServiceProtocol: Sendable {
    /// Снимки ленты. Новый снимок — после каждого изменения; частоту ограничивает потребитель.
    func snapshots() async -> AsyncStream<MessagesListSnapshot>
    /// Подписывается на изменения кэша и событие `connected`, показывает кэш и, если переписка не синхронизирована,
    /// запускает синхронизацию. Возвращается, когда кэш показан, — синхронизацию не ждёт.
    func start() async
    /// Синхронизация по требованию (pull-to-refresh) — даже если признак стоит. Возвращается, когда она закончена;
    /// ошибка приходит в снимке.
    func synchronize() async
    /// Подгружает более старые сообщения: сначала из БД, затем с сервера. Ошибка приходит в снимке.
    func loadOlder() async
    /// Уход с экрана: отменяет синхронизацию и подгрузку, дожидается снятия аренды, отписывается.
    func stop() async
}

/// Состояние ленты переписки.
struct MessagesListSnapshot: Sendable {
    /// Сообщения с сервера, сначала самые новые.
    let messages: [Message]
    let isSyncing: Bool
    let isLoadingOlder: Bool
    let hasOlder: Bool
    /// Окно прочитано из БД хотя бы раз: до этого пустое окно ещё не значит, что сообщений нет.
    let isLoaded: Bool
    /// Снимок нужно показать сразу, вне интервала обновления ленты (своё отправленное сообщение).
    let isUrgent: Bool
    /// Ошибка синхронизации или подгрузки, случившаяся к этому снимку; показывается один раз.
    let failure: Error?
}

/// Ошибки синхронизации ленты.
enum MessagesListError: Error {
    /// `getBlockBatch` не нашёл блок переписки: доступ к ней пропал между запросами.
    case blocksNotFound
}

/// Лента одной переписки: показывает кэш из БД, синхронизирует его с сервером дельтой, подгружает старые сообщения
/// и накладывает отправленные. В БД сам не пишет — передаёт данные `MessageCacheService`, а изменения получает
/// от него же после записи (`changes`), поэтому лента и БД не расходятся.
///
/// **Окно** — сообщения от самого нового до самого старого показанного блока; всегда целые блоки. Подписка
/// на изменения берётся до первого чтения из БД, а изменения, пришедшие во время чтения, копятся и накладываются
/// на прочитанное: любая запись либо попала в чтение, либо придёт после него. Перезапись кэша чужой синхронизацией,
/// пришедшая во время чтения, могла закоммититься уже после него, — окно перечитывается ещё раз.
///
/// **Синхронизация** идёт под арендой общей очереди событий: события, пришедшие во время запросов, применятся
/// после неё — уже к синхронизированной переписке. Синхронизации одного экрана не пересекаются: новая отменяет
/// идущую и ждёт её очистки. Уход с экрана (`stop`) отменяет синхронизацию и сразу снимает аренду.
///
/// Подробности — `docs/messages-sync-architecture.md`.
actor MessagesListService: MessagesListServiceProtocol {
    /// Сколько сообщений читать из БД при открытии и после синхронизации — целыми блоками.
    static let initialWindowSize = 50
    /// Сколько сообщений читать из БД при подгрузке старых — целыми блоками.
    static let olderPageSize = 40
    /// Запас для `receivedAfter`, рекомендованный сервером: повторы безвредны, слияние идемпотентно.
    static let syncMargin: Int64 = 5000

    private let conversationId: Int
    private let messageCache: MessageCacheServiceProtocol
    private let storage: MessageStorageReading
    private let messageService: MessageServiceProtocol
    private let eventQueue: RealtimeEventQueueProtocol
    private let messageSendQueue: MessageSendQueueProtocol
    /// Проверка членства: `5002` / `6002` — возможно, пользователя удалили из группы.
    private weak var membership: ConversationMembershipVerifying?

    /// Окно: сообщения по `messageId`.
    private var window: [Int: Message] = [:] {
        didSet { sortedWindow = nil }
    }
    /// Сообщения окна по убыванию `messageId`; `nil` — окно изменилось, отсортировать заново.
    private var sortedWindow: [Message]?
    /// Окно прочитано из БД хотя бы раз.
    private var isWindowLoaded = false
    /// Самый старый блок окна; `nil` — окно пусто.
    private var oldestBlockId: Int?
    /// В БД нет блоков старше окна.
    private var isStorageExhausted = false
    /// На сервере есть сообщения старше кэша.
    private var serverHasOlder = false
    private var isSyncing = false
    private var isLoadingOlder = false
    /// Номер последней запущенной синхронизации: снимает `isSyncing` только она, а не отменённая ею предыдущая.
    private var lastSyncNumber = 0

    /// Сколько чтений окна идёт сейчас; пока больше нуля, изменения копятся в `pendingChanges`.
    private var activeReads = 0
    private var pendingChanges: [MessageCacheChange] = []
    /// Синхронизации, начатые этим экраном: их `.rewritten` пропускаются — окно перечитывает сама синхронизация.
    private var ownSyncTokens: Set<UInt64> = []

    private var isStarted = false
    private var syncTask: Task<Void, Never>?
    private var loadOlderTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?
    private var sentTask: Task<Void, Never>?
    private var eventSubscription: RealtimeSubscription?
    private var snapshotContinuations: [UUID: AsyncStream<MessagesListSnapshot>.Continuation] = [:]

    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - messageCache: единственный писатель сообщений; источник изменений кэша.
    ///   - storage: чтение окна из БД.
    ///   - messageService: `getList` и `getBlockBatch`.
    ///   - eventQueue: аренда на время синхронизации и событие `connected`.
    ///   - messageSendQueue: отправленные сообщения и подтверждение доставки по результатам синхронизации.
    ///   - membership: проверка членства при ответе `5002` или `6002`.
    init(
        conversationId: Int,
        messageCache: MessageCacheServiceProtocol,
        storage: MessageStorageReading,
        messageService: MessageServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        messageSendQueue: MessageSendQueueProtocol,
        membership: ConversationMembershipVerifying?
    ) {
        self.conversationId = conversationId
        self.messageCache = messageCache
        self.storage = storage
        self.messageService = messageService
        self.eventQueue = eventQueue
        self.messageSendQueue = messageSendQueue
        self.membership = membership
    }

    // MARK: - Снимки

    /// Подписывает на снимки ленты; первый снимок — текущее состояние.
    func snapshots() -> AsyncStream<MessagesListSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: MessagesListSnapshot.self)
        let id = UUID()
        snapshotContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotSubscriber(id) }
        }
        continuation.yield(makeSnapshot(isUrgent: false, failure: nil))
        return stream
    }

    /// Отписывает подписчика на снимки.
    /// - Parameter id: подписчик.
    private func removeSnapshotSubscriber(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    /// Публикует текущее состояние ленты.
    /// - Parameters:
    ///   - isUrgent: показать сразу, вне интервала обновления.
    ///   - failure: ошибка, которую нужно показать.
    private func emit(isUrgent: Bool = false, failure: Error? = nil) {
        if let failure, failure.indicatesLostMembership, let membership {
            let conversationId = conversationId
            Task { @MainActor in membership.verifyMembership(conversationId: conversationId) }
        }
        let snapshot = makeSnapshot(isUrgent: isUrgent, failure: failure)
        snapshotContinuations.values.forEach { $0.yield(snapshot) }
    }

    /// Снимок текущего состояния: сообщения окна по убыванию `messageId`.
    /// - Parameters:
    ///   - isUrgent: показать сразу.
    ///   - failure: ошибка.
    private func makeSnapshot(isUrgent: Bool, failure: Error?) -> MessagesListSnapshot {
        let messages = sortedWindow ?? window.values.sorted { $0.messageId > $1.messageId }
        sortedWindow = messages
        return MessagesListSnapshot(
            messages: messages,
            isSyncing: isSyncing,
            isLoadingOlder: isLoadingOlder,
            hasOlder: !isStorageExhausted || serverHasOlder,
            isLoaded: isWindowLoaded,
            isUrgent: isUrgent,
            failure: failure
        )
    }

    // MARK: - Жизненный цикл

    /// Подписывается на изменения кэша, отправленные сообщения и `connected`, показывает кэш и, если переписка
    /// не синхронизирована, запускает синхронизацию. Повторный вызов без `stop()` ничего не делает.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        // Подписка — до чтения окна, и чтение начинается до первой обработки изменений: изменения, пришедшие
        // во время чтения, накопятся и наложатся на него.
        let changes = await messageCache.changes(conversationId: conversationId)
        activeReads += 1
        changesTask = Task { [weak self] in
            for await change in changes {
                await self?.apply(change)
            }
        }
        await subscribeToSentMessages()
        await subscribeToConnected()
        await readLatestWindow()
        activeReads -= 1
        isWindowLoaded = true
        if flushPendingChanges() {
            await rereadWindow(fromStart: false)
        }
        let isSynced = await messageCache.isSynced(conversationId: conversationId)
        if isStarted, !isSynced {
            startSync(lease: nil)
        }
        // Кэш при открытии показывается сразу, не дожидаясь паузы между обновлениями ленты; если нужна
        // синхронизация, снимок уже с `isSyncing` — пустая лента не мелькнёт как «сообщений нет».
        emit(isUrgent: true)
    }

    /// Уход с экрана: отписывается, отменяет синхронизацию и подгрузку и ждёт, пока синхронизация снимет аренду.
    func stop() async {
        guard isStarted else { return }
        isStarted = false
        changesTask?.cancel()
        sentTask?.cancel()
        changesTask = nil
        sentTask = nil
        if let eventSubscription {
            await eventSubscription.cancel()
            self.eventSubscription = nil
        }
        let syncTask = syncTask
        syncTask?.cancel()
        loadOlderTask?.cancel()
        await syncTask?.value
    }

    /// Накладывает на окно сообщения, созданные сервером в ответ на отправку, сразу — не дожидаясь записи в БД
    /// и независимо от признака. Снимок помечается срочным.
    private func subscribeToSentMessages() async {
        let sent = await messageSendQueue.sentMessages()
        sentTask = Task { [weak self, conversationId] in
            for await message in sent where message.conversationId == conversationId {
                await self?.applySent(message)
            }
        }
    }

    /// Применяет отправленное сообщение к окну.
    /// - Parameter message: созданное сервером сообщение.
    private func applySent(_ message: Message) {
        merge([message])
        emit(isUrgent: true)
    }

    /// Подписывается на `connected`: аренда берётся синхронно в обработчике, до первого `await`, — очередь
    /// не доставит следующее событие раньше начала синхронизации.
    private func subscribeToConnected() async {
        let queue = eventQueue
        eventSubscription = await queue.subscribe { [weak self] event in
            guard event == .connected, let self else { return }
            let lease = queue.suspendProcessing(reason: "chat.sync")
            Task { await self.synchronizeAfterConnected(lease: lease) }
        }
    }

    /// Синхронизирует после переподключения; если экран уже закрыт — сразу снимает аренду.
    /// - Parameter lease: аренда, взятая обработчиком `connected`.
    private func synchronizeAfterConnected(lease: RealtimeQueueLease) async {
        guard isStarted else {
            await lease.release()
            return
        }
        startSync(lease: lease)
    }

    // MARK: - Синхронизация

    /// Синхронизация по требованию; ждёт её окончания.
    func synchronize() async {
        guard isStarted else { return }
        await startSync(lease: nil).value
    }

    /// Запускает синхронизацию: отменяет идущую и начинает новую после её очистки. `isSyncing` ставится сразу,
    /// до взятия аренды; снимок публикует вызывающий или сама синхронизация.
    /// - Parameter lease: аренда, если её уже взял обработчик `connected`; иначе берётся внутри.
    /// - Returns: задача синхронизации.
    @discardableResult
    private func startSync(lease: RealtimeQueueLease?) -> Task<Void, Never> {
        let previous = syncTask
        previous?.cancel()
        lastSyncNumber += 1
        let number = lastSyncNumber
        isSyncing = true
        let task = Task {
            await previous?.value
            await self.runSync(lease: lease, number: number)
        }
        syncTask = task
        return task
    }

    /// Синхронизация под арендой. `endSync` и снятие аренды вызываются явно на всех путях, включая отмену:
    /// `defer` не умеет `await`.
    /// - Parameters:
    ///   - lease: уже взятая аренда; `nil` — взять.
    ///   - number: номер синхронизации из `startSync`.
    private func runSync(lease: RealtimeQueueLease?, number: Int) async {
        let lease = if let lease { lease } else { await eventQueue.suspendProcessing(reason: "chat.sync") }
        guard !Task.isCancelled, isStarted else {
            await lease.release()
            endSyncing(number: number)
            return
        }
        emit()
        let token = await messageCache.beginSync(conversationId: conversationId)
        ownSyncTokens.insert(token.id)
        let outcome: Result<MessageSyncResult, Error>
        do {
            outcome = .success(try await performSync(token: token))
        } catch {
            outcome = .failure(error)
        }
        await messageCache.endSync(token)
        await lease.release()
        await finishSync(outcome, number: number)
    }

    /// Запросы синхронизации и запись итога.
    /// - Parameter token: синхронизация.
    /// - Returns: записанный итог.
    private func performSync(token: MessageSyncToken) async throws -> MessageSyncResult {
        let result = try await fetchSyncResult()
        try Task.checkCancellation()
        try await messageCache.applySync(result, token: token)
        await messageSendQueue.removeConfirmed(by: result.messages)
        return result
    }

    /// Запрашивает дельту или, если кэша нет или дельта слишком велика, первую страницу.
    private func fetchSyncResult() async throws -> MessageSyncResult {
        guard let state = try await messageCache.cacheState(conversationId: conversationId) else {
            return .reset(firstPage: try await fetchPage(filter: .block(nil)))
        }
        let mark = state.syncMark.adding(milliseconds: -Self.syncMargin)
        let delta = try await fetchPage(filter: .receivedAfter(mark))
        // Новых сообщений больше страницы: ответ совпадает с первой страницей без фильтра.
        guard !delta.hasNext else { return .reset(firstPage: delta) }
        let updatedBlockIds = delta.updatedBlockIds ?? []
        guard updatedBlockIds.count < 10 else { return .reset(firstPage: try await fetchPage(filter: .block(nil))) }
        return .merge(messages: delta.messages, blocks: try await fetchUpdatedBlocks(updatedBlockIds))
    }

    /// Запрашивает изменённые блоки, которые есть в кэше; остальные придут актуальными при подгрузке.
    /// - Parameter blockIds: `updatedBlockIds` дельты.
    private func fetchUpdatedBlocks(_ blockIds: [Int]) async throws -> [MessageBlock] {
        guard !blockIds.isEmpty else { return [] }
        let cached = try await storage.cachedBlockIds(conversationId: conversationId, among: blockIds)
        let wanted = blockIds.filter(cached.contains)
        guard !wanted.isEmpty else { return [] }
        let batch = try await messageService.fetchBlocks(ids: wanted)
        guard batch.notFoundIds.isEmpty else { throw MessagesListError.blocksNotFound }
        return batch.blocks
    }

    /// Запрос страницы `getList`.
    /// - Parameter filter: режим.
    private func fetchPage(filter: MessageListFilter) async throws -> MessagesPage {
        try await messageService.fetchMessages(conversationId: conversationId, filter: filter)
    }

    /// После синхронизации: перечитывает окно (после сброса — с начала), показывает ошибку и, если после сброса
    /// окно короткое, догружает старые сообщения уже без аренды. Отмена ошибкой не считается.
    /// - Parameters:
    ///   - outcome: итог синхронизации.
    ///   - number: номер синхронизации.
    private func finishSync(_ outcome: Result<MessageSyncResult, Error>, number: Int) async {
        switch outcome {
        case let .success(result):
            if case .reset = result {
                await rereadWindow(fromStart: true)
            } else {
                await rereadWindow(fromStart: false)
            }
            endSyncing(number: number)
            guard isStarted, window.count < Self.initialWindowSize, serverHasOlder else { return }
            Task { await self.loadOlder() }
        case let .failure(error):
            endSyncing(number: number, failure: error.isCancellation ? nil : error)
        }
    }

    /// Синхронизация закончилась: снимает `isSyncing`, если после неё не запущена новая, и публикует снимок.
    /// - Parameters:
    ///   - number: номер закончившейся синхронизации.
    ///   - failure: ошибка, которую нужно показать.
    private func endSyncing(number: Int, failure: Error? = nil) {
        if number == lastSyncNumber {
            isSyncing = false
        }
        emit(failure: failure)
    }

    // MARK: - Подгрузка старых сообщений

    /// Подгружает более старые сообщения, если подгрузка не идёт; ждёт её окончания.
    func loadOlder() async {
        guard isStarted, loadOlderTask == nil, !isStorageExhausted || serverHasOlder else { return }
        isLoadingOlder = true
        emit()
        let task = Task { await self.runLoadOlder() }
        loadOlderTask = task
        await task.value
        loadOlderTask = nil
        isLoadingOlder = false
        emit()
    }

    /// Подгрузка без аренды: сначала из БД (эта часть кэша непрерывна), затем с сервера.
    private func runLoadOlder() async {
        do {
            guard try await !loadOlderFromStorage() else { return }
            try await loadOlderFromServer()
        } catch {
            guard !error.isCancellation else { return }
            emit(failure: error)
        }
    }

    /// Дописывает к окну блоки из БД старше окна.
    /// - Returns: `true` — что-то дописано.
    private func loadOlderFromStorage() async throws -> Bool {
        guard !isStorageExhausted, let oldestBlockId else { return false }
        let older = try await readWindow {
            try await self.storage.fetchBlocks(conversationId: self.conversationId, olderThan: oldestBlockId, minCount: Self.olderPageSize)
        }
        isStorageExhausted = older.count < Self.olderPageSize
        merge(older)
        if flushPendingChanges() {
            await rereadWindow(fromStart: false)
        }
        return !older.isEmpty
    }

    /// Запрашивает у сервера страницы старше кэша, пропуская пустые, и дописывает первую непустую к кэшу
    /// и окну. Если кэш за время запроса сброшен, страница не применяется — окно перечитает синхронизация.
    private func loadOlderFromServer() async throws {
        while true {
            guard let state = try await messageCache.cacheState(conversationId: conversationId),
                  state.hasMorePages, let nextBlockId = state.nextBlockId else {
                serverHasOlder = false
                return
            }
            let page = try await fetchPage(filter: .block(nextBlockId))
            try Task.checkCancellation()
            let isAppended = try await messageCache.appendOlderPage(page, requestedBlockId: nextBlockId, conversationId: conversationId)
            guard isAppended else { return }
            await messageSendQueue.removeConfirmed(by: page.messages)
            isStorageExhausted = true
            serverHasOlder = page.hasNext && page.nextBlockId != nil
            merge(page.messages)
            guard page.messages.isEmpty, serverHasOlder else { return }
        }
    }

    // MARK: - Окно

    /// Читает самые новые блоки из БД и заменяет ими окно. Ошибка чтения не показывается: лента дождётся сервера.
    private func readLatestWindow() async {
        do {
            let latest = try await storage.fetchLatestBlocks(conversationId: conversationId, minCount: Self.initialWindowSize)
            let state = try await messageCache.cacheState(conversationId: conversationId)
            replaceWindow(with: latest)
            isStorageExhausted = latest.count < Self.initialWindowSize
            serverHasOlder = state?.hasMorePages ?? false
        } catch {
            Logger.storage.error("Не удалось прочитать сообщения из БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Перечитывает окно из БД с прежней глубины — так удаления и сброс отражаются в ленте без отдельной логики.
    /// Если во время чтения кэш перезаписала чужая синхронизация, читает ещё раз.
    /// - Parameter fromStart: окно читается заново с самых новых блоков (после сброса кэша).
    private func rereadWindow(fromStart: Bool) async {
        var fromStart = fromStart
        repeat {
            await readWindowFromStorage(fromStart: fromStart)
            fromStart = false
        } while flushPendingChanges()
        emit()
    }

    /// Одно перечитывание окна из БД; изменения, пришедшие во время него, копятся.
    /// - Parameter fromStart: читать с самых новых блоков, а не с прежней глубины.
    private func readWindowFromStorage(fromStart: Bool) async {
        if !fromStart, let oldestBlockId {
            do {
                let messages = try await readWindow {
                    try await self.storage.fetchMessages(conversationId: self.conversationId, fromBlockId: oldestBlockId)
                }
                replaceWindow(with: messages)
                serverHasOlder = try await messageCache.cacheState(conversationId: conversationId)?.hasMorePages ?? false
            } catch {
                Logger.storage.error("Не удалось перечитать сообщения из БД: \(String(describing: error), privacy: .public)")
            }
        } else {
            await readWindow { await self.readLatestWindow() }
        }
    }

    /// Выполняет чтение окна, копя изменения, пришедшие во время него.
    /// - Parameter read: чтение.
    private func readWindow<T>(_ read: () async throws -> T) async rethrows -> T {
        activeReads += 1
        defer { activeReads -= 1 }
        return try await read()
    }

    /// Заменяет окно прочитанными сообщениями.
    /// - Parameter messages: сообщения из БД.
    private func replaceWindow(with messages: [Message]) {
        window = Dictionary(messages.map { ($0.messageId, $0) }, uniquingKeysWith: { first, _ in first })
        oldestBlockId = messages.map(\.blockId).min()
    }

    /// Сливает сообщения с окном: из двух версий остаётся та, что не старше.
    /// - Parameter messages: сообщения.
    private func merge(_ messages: [Message]) {
        for message in messages {
            guard window[message.messageId].map(message.isNotOlder(than:)) ?? true else { continue }
            window[message.messageId] = message
        }
        let oldest = messages.map(\.blockId).min()
        oldestBlockId = [oldestBlockId, oldest].compactMap { $0 }.min()
    }

    /// Применяет изменение кэша к окну; во время чтения окна — откладывает.
    /// - Parameter change: изменение.
    private func apply(_ change: MessageCacheChange) async {
        guard activeReads == 0 else {
            pendingChanges.append(change)
            return
        }
        switch change {
        case let .upserted(messages):
            applyUpserted(messages)
            emit()
        case let .rewritten(token):
            guard !ownSyncTokens.contains(token.id) else { return }
            await rereadWindow(fromStart: false)
        }
    }

    /// Применяет изменения, накопленные за время чтения.
    /// - Returns: `true` — среди них есть перезапись кэша чужой синхронизацией: чтение могло пройти до её коммита
    ///   или затронуть не всё окно, и окно нужно перечитать. `.rewritten` своих синхронизаций перечитывают они сами.
    private func flushPendingChanges() -> Bool {
        guard activeReads == 0 else { return false }
        let changes = pendingChanges
        pendingChanges = []
        var needsReread = false
        for change in changes {
            switch change {
            case let .upserted(messages):
                applyUpserted(messages)
            case let .rewritten(token):
                needsReread = needsReread || !ownSyncTokens.contains(token.id)
            }
        }
        return needsReread
    }

    /// Сливает записанные сообщения с окном: новее окна и в пределах окна — сливаются, старше окна — пропускаются:
    /// они придут при подгрузке из БД.
    /// - Parameter messages: версии из БД.
    private func applyUpserted(_ messages: [Message]) {
        let visible = messages.filter { message in
            guard let oldestBlockId else { return true }
            return message.blockId >= oldestBlockId
        }
        merge(visible)
    }

}
