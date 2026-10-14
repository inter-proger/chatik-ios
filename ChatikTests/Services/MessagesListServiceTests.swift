//
//  MessagesListServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

@MainActor
final class MessagesListServiceTests: XCTestCase {
    private var storage: MessageStorageService!
    /// Чтение БД лентой; ответ на подгрузку старых блоков можно задержать.
    private var reader: GatedStorageReader!
    private var monitor: RealtimeConnectionMonitor!
    private var cache: MessageCacheService!
    private var messageService: MessageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var sendQueue: MessageSendQueueMock!
    private var sut: MessagesListService!
    private var recorder: SnapshotRecorder!

    override func setUp() async throws {
        try await super.setUp()
        storage = MessageStorageService(container: CoreDataStack.makeContainer(inMemory: true))
        monitor = RealtimeConnectionMonitor()
        monitor.connect()
        cache = MessageCacheService(storage: storage, connectionMonitor: monitor)
        reader = GatedStorageReader(storage: storage)
        messageService = MessageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        sendQueue = MessageSendQueueMock()
        sut = MessagesListService(
            conversationId: 1,
            messageCache: cache,
            storage: reader,
            messageService: messageService,
            eventQueue: eventQueue,
            messageSendQueue: sendQueue
        )
        recorder = SnapshotRecorder()
        await recorder.record(await sut.snapshots())
    }

    override func tearDown() async throws {
        await sut.stop()
        recorder.stop()
        try await super.tearDown()
    }

    // MARK: - Открытие

    /// Кейс: в кэше есть сообщения, переписка не синхронизирована, запрос дельты ещё идёт.
    /// Ожидание: кэш показан до ответа сервера срочным снимком (без паузы обновления), идёт синхронизация.
    func test_start_showsCacheBeforeNetwork() async throws {
        try await writeCache([.make(id: 2), .make(id: 1)])
        let gate = Gate()
        messageService.onFetch = { await gate.wait() }
        messageService.stubbedPages = [.success(delta([]))]

        await sut.start()
        await waitUntil { gate.isWaiting }

        XCTAssertEqual(recorder.latest?.messages.map(\.id), [2, 1])
        XCTAssertEqual(recorder.latest?.isSyncing, true)
        XCTAssertTrue(recorder.urgentMessageIds.contains([2, 1]))
        gate.open()
        await waitUntil { [unowned self] in recorder.latest?.isSyncing == false }
    }

    /// Кейс: кэша нет, переписка не синхронизирована, запрос первой страницы ещё идёт.
    /// Ожидание: до прочтения кэша снимок помечен непрочитанным; первый снимок после прочтения — уже
    /// с синхронизацией: ни один снимок не выглядит как «окно прочитано, синхронизации нет, сообщений нет».
    func test_start_withoutCache_neverLooksEmptyBeforeSync() async throws {
        let gate = Gate()
        messageService.onFetch = { await gate.wait() }
        messageService.stubbedPages = [.success(MessagesPage(messages: [], nextBlockId: nil, hasNext: false))]

        await sut.start()
        await waitUntil { gate.isWaiting }

        XCTAssertEqual(recorder.all.first?.isLoaded, false)
        XCTAssertFalse(recorder.all.contains { $0.isLoaded && !$0.isSyncing && $0.messages.isEmpty })
        XCTAssertEqual(recorder.latest?.isSyncing, true)
        gate.open()
        await waitForSyncToFinish()
    }

    /// Кейс: переписка уже синхронизирована в этом соединении.
    /// Ожидание: кэш показан, в сеть экран не ходит.
    func test_start_synced_doesNotFetch() async throws {
        try await makeSynced([.make(id: 1)])

        await sut.start()
        await yieldTimes()

        XCTAssertEqual(recorder.latest?.messages.map(\.id), [1])
        XCTAssertTrue(messageService.pageRequests.isEmpty)
    }

    // MARK: - Синхронизация

    /// Кейс: кэша нет.
    /// Ожидание: первая страница без фильтра, кэш заменён ею, синхронизация под арендой, аренда снята.
    func test_sync_withoutCache_loadsFirstPage() async throws {
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false))]

        await sut.start()
        await waitForSyncToFinish()

        XCTAssertEqual(messageService.pageRequests.map(\.filter), [.block(nil)])
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [2, 1])
        XCTAssertEqual(eventQueue.leaseReasons.map { "\($0)" }, ["chat.sync"])
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
    }

    /// Кейс: в кэше отметка; сервер вернул дельту с новым сообщением.
    /// Ожидание: дельта запрошена с запасом 5 с, новое сообщение добавлено к кэшу, кэш остался.
    func test_sync_delta_mergesWithMargin() async throws {
        try await writeCache([.make(id: 1)], syncMark: .stub(10_000))
        messageService.stubbedPages = [.success(delta([.make(id: 2, createdAt: .stub(12_000))]))]

        await sut.start()
        await waitForSyncToFinish()

        XCTAssertEqual(messageService.pageRequests.map(\.filter), [.receivedAfter(.stub(5000))])
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [2, 1])
    }

    /// Кейс: дельта ответила `hasNext: true` — новых сообщений больше страницы.
    /// Ожидание: кэш сброшен этой страницей — старые сообщения из кэша ушли, повторного запроса нет.
    func test_sync_deltaHasNext_resetsWithDeltaPage() async throws {
        try await writeCache([.make(id: 1)])
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 60, blockId: 5)], nextBlockId: 4, hasNext: true))]
        messageService.stubbedPages.append(.success(MessagesPage(messages: [.make(id: 50, blockId: 4)], nextBlockId: nil, hasNext: false)))

        await sut.start()
        await waitForSyncToFinish()
        await waitUntil { [unowned self] in recorder.latest?.isLoadingOlder == false && messageService.pageRequests.count == 2 }

        XCTAssertEqual(messageService.pageRequests.first?.filter, .receivedAfter(.stub(-5000)))
        XCTAssertEqual(messageService.pageRequests.last?.filter, .block(4))
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [60, 50])
    }

    /// Кейс: дельта без новых сообщений, но изменилось ровно 10 блоков.
    /// Ожидание: кэш сброшен первой страницей без фильтра.
    func test_sync_tenUpdatedBlocks_resetsWithFullLoad() async throws {
        try await writeCache([.make(id: 1)])
        messageService.stubbedPages = [
            .success(delta([], updatedBlockIds: Array(1...10))),
            .success(MessagesPage(messages: [.make(id: 3)], nextBlockId: nil, hasNext: false)),
        ]

        await sut.start()
        await waitForSyncToFinish()

        XCTAssertEqual(messageService.pageRequests.last?.filter, .block(nil))
        XCTAssertTrue(messageService.blockRequests.isEmpty)
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [3])
    }

    /// Кейс: изменились блоки 7 (нет в кэше) и 2 (есть); в блоке 2 сообщение отредактировано, другое удалено.
    /// Ожидание: запрошен только блок 2, он применён целиком.
    func test_sync_updatedBlocks_fetchesOnlyCachedAndApplies() async throws {
        try await writeCache([.make(id: 3, blockId: 2), .make(id: 2, blockId: 2), .make(id: 1, blockId: 1)])
        let edited = Message.make(id: 3, text: "Исправлено", blockId: 2, updatedAt: .stub(1000))
        messageService.stubbedPages = [.success(delta([], updatedBlockIds: [7, 2]))]
        messageService.stubbedBatches = [.success(MessageBlocksBatch(
            blocks: [MessageBlock(blockId: 2, conversationId: 1, messages: [edited], updatedAt: .stub(1000))],
            notFoundIds: []
        ))]

        await sut.start()
        await waitForSyncToFinish()

        XCTAssertEqual(messageService.blockRequests, [[2]])
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [3, 1])
        XCTAssertEqual(recorder.latest?.messages.first?.text, "Исправлено")
    }

    /// Кейс: `getBlockBatch` не удался.
    /// Ожидание: в кэш ничего не записано — ни новые сообщения, ни отметка; ошибка пришла в снимке; аренда снята.
    func test_sync_blockBatchFailure_writesNothing() async throws {
        try await writeCache([.make(id: 1, blockId: 1)], syncMark: .stub)
        messageService.stubbedPages = [.success(delta([.make(id: 2, createdAt: .stub(5000), blockId: 2)], updatedBlockIds: [1]))]
        messageService.stubbedBatches = [.failure(NetworkError.transport(URLError(.timedOut)))]

        await sut.start()
        await waitForSyncToFinish()

        let state = try await storage.fetchState(conversationId: 1)
        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(state?.syncMark, .stub)
        XCTAssertEqual(stored.map(\.id), [1])
        XCTAssertNotNil(recorder.failures.first)
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
    }

    /// Кейс: `getBlockBatch` не нашёл блок — доступ к переписке пропал между запросами.
    /// Ожидание: синхронизация — ошибка, кэш не тронут.
    func test_sync_notFoundBlocks_failsWithoutWriting() async throws {
        try await writeCache([.make(id: 1, blockId: 1)], syncMark: .stub)
        messageService.stubbedPages = [.success(delta([], updatedBlockIds: [1]))]
        messageService.stubbedBatches = [.success(MessageBlocksBatch(blocks: [], notFoundIds: [1]))]

        await sut.start()
        await waitForSyncToFinish()

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(stored.map(\.id), [1])
        XCTAssertTrue(recorder.failures.first is MessagesListError)
    }

    /// Кейс: синхронизация получила сообщения.
    /// Ожидание: они переданы очереди отправки — она уберёт уже доставленные.
    func test_sync_confirmsOutgoingInQueue() async throws {
        let page = [Message.make(id: 2, clientId: "c1")]
        messageService.stubbedPages = [.success(MessagesPage(messages: page, nextBlockId: nil, hasNext: false))]

        await sut.start()
        await waitForSyncToFinish()

        XCTAssertEqual(sendQueue.confirmedBatches, [page])
    }

    /// Кейс: синхронизация закончилась, переписка синхронизирована; затем кэш записал событие.
    /// Ожидание: сообщение из события появилось в ленте.
    func test_cacheChange_afterSync_appearsInFeed() async throws {
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.start()
        await waitForSyncToFinish()
        let message = Message.make(id: 2)

        await cache.handle(.messageReceived(message, LastMessage(message: message)))

        await waitUntil { [unowned self] in recorder.latest?.messages.map(\.id) == [2, 1] }
    }

    /// Кейс: кэш записал правку сообщения из блока старше окна.
    /// Ожидание: в ленту оно не попало — придёт при подгрузке из БД.
    func test_cacheChange_olderThanWindow_isIgnored() async throws {
        let window = (1...50).map { Message.make(id: 100 + $0, blockId: 10) }
        try await makeSynced(window.reversed() + [.make(id: 1, blockId: 1)])
        await sut.start()
        await waitUntil { [unowned self] in recorder.latest?.messages.count == 50 }

        await cache.handle(.messageEdited(.make(id: 1, blockId: 1, updatedAt: .stub(1000)), nil))
        await cache.waitForWrites()
        await yieldTimes()

        XCTAssertEqual(recorder.latest?.messages.count, 50)
        XCTAssertFalse(recorder.latest?.messages.contains { $0.id == 1 } ?? true)
    }

    // MARK: - connected и отмена

    /// Кейс: идёт синхронизация; пришло `connected`.
    /// Ожидание: аренда взята сразу в обработчике; идущая синхронизация отменена и очищена, затем прошла новая;
    /// все аренды сняты.
    func test_connected_restartsSync() async throws {
        let gate = Gate()
        messageService.onFetch = { await gate.wait() }
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false)),
            .success(MessagesPage(messages: [.make(id: 2)], nextBlockId: nil, hasNext: false)),
        ]
        await sut.start()
        await waitUntil { gate.isWaiting }

        await eventQueue.send(.connected)
        XCTAssertEqual(eventQueue.activeLeaseCount, 2)
        messageService.onFetch = nil
        gate.open()

        await waitUntil { [unowned self] in messageService.pageRequests.count == 2 && eventQueue.activeLeaseCount == 0 }
        await waitForSyncToFinish()
        XCTAssertEqual(recorder.latest?.messages.map(\.id), [2])
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    /// Кейс: идёт запрос синхронизации; экран закрыт (`stop`).
    /// Ожидание: `stop` вернулся, когда аренда снята; ответ отменённой синхронизации не записан.
    func test_stop_duringSync_releasesLeaseAndWritesNothing() async throws {
        let gate = Gate()
        messageService.onFetch = { await gate.wait() }
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.start()
        await waitUntil { gate.isWaiting }

        let stop = Task { await self.sut.stop() }
        await yieldTimes()
        gate.open()
        await stop.value

        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
        XCTAssertNil(state)
    }

    /// Кейс: `connected` пришло после ухода с экрана.
    /// Ожидание: синхронизации нет, аренда не висит.
    func test_connected_afterStop_doesNotSync() async throws {
        try await makeSynced([])
        await sut.start()
        await sut.stop()

        await eventQueue.send(.connected)
        await yieldTimes()

        XCTAssertTrue(messageService.pageRequests.isEmpty)
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
    }

    // MARK: - Подгрузка

    /// Кейс: в кэше 60 сообщений (окно — 50 целыми блоками), на сервере есть более старые.
    /// Ожидание: первая подгрузка — из БД без сети, вторая — с сервера по `nextBlockId`.
    func test_loadOlder_readsStorageThenServer() async throws {
        let cached = (1...60).map { Message.make(id: 100 + $0, blockId: 10 + ($0 - 1) / 10) }.reversed()
        try await makeSynced(Array(cached), nextBlockId: 9)
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 50, blockId: 9)], nextBlockId: nil, hasNext: false))]
        await sut.start()
        await waitUntil { [unowned self] in recorder.latest?.messages.count == 50 }

        await sut.loadOlder()
        await waitUntil { [unowned self] in recorder.latest?.messages.count == 60 }
        XCTAssertTrue(messageService.pageRequests.isEmpty)
        await sut.loadOlder()

        await waitUntil { [unowned self] in recorder.latest?.messages.count == 61 && recorder.latest?.isLoadingOlder == false }
        XCTAssertEqual(messageService.pageRequests.map(\.filter), [.block(9)])
        XCTAssertEqual(recorder.latest?.hasOlder, false)
    }

    /// Кейс: идёт подгрузка старых сообщений из БД; пока её ответ не вернулся, другой экран той же переписки
    /// сбросил кэш своей синхронизацией.
    /// Ожидание: после подгрузки окно перечитано — в ленте только данные сброса, а не прежний кэш.
    func test_loadOlder_foreignResetDuringRead_rereadsWindow() async throws {
        let cached = (1...60).map { Message.make(id: 100 + $0, blockId: 10 + ($0 - 1) / 10) }.reversed()
        try await makeSynced(Array(cached))
        await sut.start()
        await waitUntil { [unowned self] in recorder.latest?.messages.count == 50 }
        let gate = Gate()
        reader.olderBlocksGate = gate

        let loading = Task { await sut.loadOlder() }
        await waitUntil { gate.isWaiting }
        try await makeSynced([.make(id: 300, blockId: 30)])
        gate.open()
        await loading.value

        await waitUntil { [unowned self] in recorder.latest?.messages.map(\.id) == [300] }
    }

    /// Кейс: на сервере старше кэша пустая страница с `hasNext: true`, за ней — страница с сообщением.
    /// Ожидание: пустая страница не остановила подгрузку — сообщение получено.
    func test_loadOlder_skipsEmptyPages() async throws {
        try await makeSynced([.make(id: 10, blockId: 5)], nextBlockId: 4)
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [], nextBlockId: 3, hasNext: true)),
            .success(MessagesPage(messages: [.make(id: 2, blockId: 3)], nextBlockId: nil, hasNext: false)),
        ]
        await sut.start()

        await sut.loadOlder()

        await waitUntil { [unowned self] in recorder.latest?.messages.map(\.id) == [10, 2] }
        XCTAssertEqual(messageService.pageRequests.map(\.filter), [.block(4), .block(3)])
    }

    // MARK: - Отправка

    /// Кейс: очередь опубликовала отправленное сообщение этой и другой переписки.
    /// Ожидание: сообщение этой переписки сразу в ленте, снимок срочный; чужое — нет.
    func test_sentMessage_appliedImmediatelyAsUrgent() async throws {
        try await makeSynced([.make(id: 1)])
        await sut.start()
        await waitUntil { [unowned self] in sendQueue.subscriberCount == 1 }

        sendQueue.publishSent(.make(id: 9, conversationId: 2))
        sendQueue.publishSent(.make(id: 2))

        await waitUntil { [unowned self] in recorder.latest?.messages.map(\.id) == [2, 1] }
        XCTAssertEqual(recorder.latest?.isUrgent, true)
    }

    // MARK: - Helpers

    /// Ждёт конца синхронизации: снимок без `isSyncing` после того, как она началась.
    private func waitForSyncToFinish() async {
        await waitUntil { [unowned self] in recorder.didSync && recorder.latest?.isSyncing == false }
    }

    /// Записывает кэш переписки 1: сообщения и состояние.
    /// - Parameters:
    ///   - messages: сообщения.
    ///   - syncMark: отметка.
    ///   - nextBlockId: продолжение подгрузки с сервера.
    private func writeCache(_ messages: [Message], syncMark: ServerTime = .stub, nextBlockId: Int? = nil) async throws {
        let state = MessageCacheState(syncMark: syncMark, nextBlockId: nextBlockId, hasMorePages: nextBlockId != nil)
        _ = try await storage.write(MessageStorageChanges(
            upserts: messages,
            stateChanges: [MessageCacheStateChange(conversationId: 1, kind: .replace(state))]
        ))
    }

    /// Делает переписку 1 синхронизированной в текущем соединении с заданным кэшем.
    /// - Parameters:
    ///   - messages: первая страница, сначала самые новые.
    ///   - nextBlockId: продолжение подгрузки с сервера.
    private func makeSynced(_ messages: [Message], nextBlockId: Int? = nil) async throws {
        let token = await cache.beginSync(conversationId: 1)
        let page = MessagesPage(messages: messages, nextBlockId: nextBlockId, hasNext: nextBlockId != nil)
        try await cache.applySync(.reset(firstPage: page), token: token)
        await cache.endSync(token)
    }

    /// Ответ дельты без продолжения.
    /// - Parameters:
    ///   - messages: новые сообщения.
    ///   - updatedBlockIds: изменённые блоки.
    private func delta(_ messages: [Message], updatedBlockIds: [Int] = []) -> MessagesPage {
        MessagesPage(messages: messages, nextBlockId: nil, hasNext: false, updatedBlockIds: updatedBlockIds)
    }
}

/// Запоминает снимки ленты.
@MainActor
private final class SnapshotRecorder {
    private(set) var latest: MessagesListSnapshot?
    /// Ошибки из снимков по порядку.
    private(set) var failures: [Error] = []
    /// Синхронизация хотя бы раз начиналась.
    private(set) var didSync = false
    /// Сообщения срочных снимков по порядку.
    private(set) var urgentMessageIds: [[Int]] = []
    /// Все снимки по порядку.
    private(set) var all: [MessagesListSnapshot] = []
    private var task: Task<Void, Never>?

    /// Начинает запоминать снимки потока; возвращается, когда получен первый.
    /// - Parameter snapshots: поток снимков.
    func record(_ snapshots: AsyncStream<MessagesListSnapshot>) async {
        let (first, firstContinuation) = AsyncStream.makeStream(of: Void.self)
        task = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
                firstContinuation.yield()
            }
        }
        for await _ in first { break }
    }

    /// Запоминает снимок.
    /// - Parameter snapshot: снимок.
    private func apply(_ snapshot: MessagesListSnapshot) {
        latest = snapshot
        all.append(snapshot)
        didSync = didSync || snapshot.isSyncing
        if snapshot.isUrgent {
            urgentMessageIds.append(snapshot.messages.map(\.id))
        }
        if let failure = snapshot.failure {
            failures.append(failure)
        }
    }

    /// Прекращает запоминать снимки.
    func stop() {
        task?.cancel()
    }
}

/// Чтение БД, ответ которого на подгрузку старых блоков можно задержать шлагбаумом: так изменения кэша приходят
/// во время чтения окна. `@unchecked Sendable`: шлагбаум задаёт тест до чтения.
private final class GatedStorageReader: MessageStorageReading, @unchecked Sendable {
    private let storage: MessageStorageService
    /// Шлагбаум после чтения старых блоков; `nil` — ответ сразу.
    var olderBlocksGate: Gate?

    /// - Parameter storage: настоящее хранилище.
    init(storage: MessageStorageService) {
        self.storage = storage
    }

    func fetchState(conversationId: Int) async throws -> MessageCacheState? {
        try await storage.fetchState(conversationId: conversationId)
    }

    func fetchLatestBlocks(conversationId: Int, minCount: Int) async throws -> [Message] {
        try await storage.fetchLatestBlocks(conversationId: conversationId, minCount: minCount)
    }

    func fetchBlocks(conversationId: Int, olderThan beforeBlockId: Int, minCount: Int) async throws -> [Message] {
        let messages = try await storage.fetchBlocks(conversationId: conversationId, olderThan: beforeBlockId, minCount: minCount)
        if let olderBlocksGate {
            await olderBlocksGate.wait()
        }
        return messages
    }

    func fetchMessages(conversationId: Int, fromBlockId: Int) async throws -> [Message] {
        try await storage.fetchMessages(conversationId: conversationId, fromBlockId: fromBlockId)
    }

    func cachedBlockIds(conversationId: Int, among blockIds: [Int]) async throws -> Set<Int> {
        try await storage.cachedBlockIds(conversationId: conversationId, among: blockIds)
    }
}
