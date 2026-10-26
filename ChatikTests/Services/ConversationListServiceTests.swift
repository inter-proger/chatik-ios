//
//  ConversationListServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ConversationListServiceTests: XCTestCase {
    private var conversationService: ConversationServiceMock!
    private var storage: ConversationStorageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var userCache: UserCacheServiceMock!
    private var sut: ConversationListService!

    /// Состояние загруженного списка: водяной знак позиции — `ServerTime.stub`, курсор изменений — 10.
    private let loadedState = ConversationListState(
        isLoaded: true,
        hasMorePages: true,
        positionWatermark: .stub,
        positionWatermarkCeiling: nil,
        syncedChangeVersion: 10
    )

    override func setUp() async throws {
        try await super.setUp()
        conversationService = ConversationServiceMock()
        storage = ConversationStorageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        userCache = UserCacheServiceMock()
        sut = makeSUT()
    }

    // MARK: - Кэш

    /// Кейс: в БД две переписки (личная и групповая) и состояние загруженного списка.
    /// Ожидание: после старта список показан из кэша в порядке БД, собеседник личной передан кэшу пользователей,
    /// следующая страница пойдёт со сдвигом, равным числу переписок кэша.
    func test_start_showsCacheAndLoadsOpponents() async throws {
        let cached = [Conversation.make(id: 2, position: .stub(10)), Conversation.singleStub]
        await start(cache: cached, state: loadedState)

        await yieldUntil { [unowned self] in !userCache.loadRequests.isEmpty }
        conversationService.stubbedPages = [.success(page([]))]
        sut.loadNextPageIfNeeded(currentConversationId: 1)
        await yieldUntil { [unowned self] in !conversationService.requests.isEmpty }

        XCTAssertEqual(sut.conversations, cached)
        XCTAssertEqual(userCache.loadRequests, [[2]])
        XCTAssertEqual(conversationService.requests.first?.filter, .none(offset: 2))
        XCTAssertEqual(eventQueue.subscriberCount, 1)
    }

    /// Кейс: `connected` пришёл, пока кэш ещё читается.
    /// Ожидание: аренда очереди взята сразу, а запрос синхронизации ушёл только после чтения кэша — и это дельта
    /// от сохранённого водяного знака, а не полная загрузка.
    func test_connectedBeforeCacheLoaded_waitsForCache() async {
        let gate = Gate()
        storage.stubbedList = .success(([.make(id: 1)], loadedState))
        storage.onFetchList = { await gate.wait() }
        conversationService.stubbedPages = [.success(page([])), .success(page([]))]
        sut.start()
        await yieldUntil { gate.isWaiting }

        let connected = Task { [eventQueue] in await eventQueue!.send(.connected) }
        await connected.value
        XCTAssertEqual(eventQueue.activeLeaseCount, 1)
        XCTAssertTrue(conversationService.requests.isEmpty)
        gate.open()

        await yieldUntil { [unowned self] in !conversationService.requests.isEmpty }
        XCTAssertEqual(conversationService.requests.first?.filter, .positionUpdatedAfter(ServerTime.stub.adding(milliseconds: -5000), offset: nil))
    }

    // MARK: - Полная загрузка

    /// Кейс: первый запуск — кэш пуст, список не загружен; пришёл `connected`.
    /// Ожидание: первая страница без фильтра заменила список и БД; водяной знак позиции — максимум страницы, курсор
    /// изменений и общий счётчик — из ответа; индикатор и аренда сняты.
    func test_connected_notLoaded_loadsFirstPage() async {
        await start()
        let newest = Conversation.make(id: 1, position: .stub(50), updatedInfoAt: .stub(5))
        let older = Conversation.make(id: 2, position: .stub(10), updatedInfoAt: .stub(70))
        conversationService.stubbedPages = [.success(page([newest, older], hasNext: true, totalUnread: 3))]

        await connect()

        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: nil)])
        XCTAssertEqual(conversationService.requests.first?.count, ConversationListService.pageSize)
        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
        XCTAssertTrue(sut.hasMorePages)
        await yieldUntil { [unowned self] in storage.replacements.count == 1 }
        XCTAssertEqual(storage.replacements.first?.state, ConversationListState(
            isLoaded: true, hasMorePages: true, positionWatermark: .stub(50), positionWatermarkCeiling: nil,
            syncedChangeVersion: 10, totalUnreadCount: 3, totalUnreadVersion: 10
        ))
    }

    /// Кейс: идёт запрос стартовой синхронизации.
    /// Ожидание: индикатор «Обновление…» поднят и аренда держит очередь; после ответа оба сняты.
    func test_connected_whileRequesting_isSyncingAndHoldsLease() async {
        await start()
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 1)]))]
        conversationService.onRequest = { await gate.wait() }

        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }

        XCTAssertTrue(sut.isSyncing)
        XCTAssertEqual(eventQueue.activeLeaseCount, 1)
        XCTAssertEqual(eventQueue.leaseReasons.map(String.init(describing:)), ["conversationList.sync"])
        gate.open()
        await yieldUntil { [unowned self] in !sut.isSyncing && eventQueue.activeLeaseCount == 0 }
    }

    /// Кейс: запрос стартовой синхронизации упал с ошибкой сети.
    /// Ожидание: кэш остаётся на экране, индикатор и аренда сняты.
    func test_connected_networkError_keepsCacheAndReleasesLease() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        conversationService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await connect()

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertTrue(storage.replacements.isEmpty)
    }

    // MARK: - Синхронизация при открытии экрана

    /// Кейс: экран открыт, `connected` ещё не приходил; кэш загруженного списка читается дольше обычного.
    /// Ожидание: запрос ушёл только после чтения кэша и это дельта позиций; повторный вызов ничего не запрашивает.
    func test_synchronizeIfNeeded_withoutConnected_waitsForCacheAndSyncsOnce() async throws {
        let gate = Gate()
        storage.stubbedList = .success(([.make(id: 1)], loadedState))
        storage.onFetchList = { await gate.wait() }
        conversationService.stubbedPages = [.success(page([]))]
        sut.start()
        await yieldUntil { gate.isWaiting }

        let sync = Task { [sut] in try await sut!.synchronizeIfNeeded() }
        await yieldTimes()
        XCTAssertTrue(conversationService.requests.isEmpty)
        gate.open()
        try await sync.value
        try await sut.synchronizeIfNeeded()

        XCTAssertEqual(conversationService.requests.map(\.filter), [.positionUpdatedAfter(ServerTime.stub.adding(milliseconds: -5000), offset: nil)])
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
        XCTAssertFalse(sut.isSyncing)
    }

    /// Кейс: синхронизация в сессии уже была — по `connected`.
    /// Ожидание: `synchronizeIfNeeded()` ничего не запрашивает.
    func test_synchronizeIfNeeded_afterConnectedSync_doesNothing() async throws {
        await start(cache: [.make(id: 1)], state: loadedState)
        conversationService.stubbedPages = [.success(page([]))]
        await connect()

        try await sut.synchronizeIfNeeded()

        XCTAssertEqual(conversationService.requests.count, 1)
    }

    /// Кейс: первый вход — кэш пуст; `synchronizeIfNeeded()` упал с ошибкой сети.
    /// Ожидание: ошибка проброшена, список не загружен; индикатор и аренда сняты.
    func test_synchronizeIfNeeded_networkError_throws() async {
        await start()
        conversationService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        do {
            try await sut.synchronizeIfNeeded()
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        XCTAssertFalse(sut.isLoaded)
        XCTAssertFalse(sut.isSyncing)
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
    }

    /// Кейс: идёт синхронизация из `synchronizeIfNeeded()`, пришёл `connected`.
    /// Ожидание: `synchronizeIfNeeded()` завершается `CancellationError` — список обновит новая синхронизация.
    func test_synchronizeIfNeeded_interruptedByConnected_throwsCancellation() async {
        await start()
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 7)])), .success(page([.make(id: 2)]))]
        conversationService.onRequest = { [unowned self] in
            if conversationService.requests.count == 1 { await gate.wait() }
        }
        let sync = Task { [sut] in try await sut!.synchronizeIfNeeded() }
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.connected)
        await yieldUntil { [unowned self] in conversationService.requests.count == 2 && !sut.isSyncing }
        gate.open()
        let result = await sync.result

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(sut.conversations.map(\.id), [2])
    }

    /// Кейс: синхронизация прошла, затем выход из аккаунта и повторный вход.
    /// Ожидание: в новой сессии `synchronizeIfNeeded()` снова загружает список, `isLoaded` до этого сброшен.
    func test_synchronizeIfNeeded_afterLogout_syncsAgain() async throws {
        await start()
        conversationService.stubbedPages = [.success(page([.make(id: 1)])), .success(page([.make(id: 2)]))]
        try await sut.synchronizeIfNeeded()
        XCTAssertTrue(sut.isLoaded)

        await sut.authServiceWillLogout()
        XCTAssertFalse(sut.isLoaded)
        try await sut.synchronizeIfNeeded()

        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: nil), .none(offset: nil)])
        XCTAssertEqual(sut.conversations.map(\.id), [2])
    }

    // MARK: - Запись до чтения кэша

    /// Кейс: переписка применена (`apply`), пока кэш со состоянием загруженного списка ещё читается; затем
    /// применена ещё одна — уже после чтения.
    /// Ожидание: первая запись — только переписка, без состояния (иначе затёрлись бы водяные знаки); вторая —
    /// с прочитанным состоянием.
    func test_apply_beforeCacheLoaded_doesNotOverwriteState() async {
        let gate = Gate()
        storage.stubbedList = .success(([.make(id: 1)], loadedState))
        storage.onFetchList = { await gate.wait() }
        sut.start()
        await yieldUntil { gate.isWaiting }

        sut.apply(.make(id: 2, position: .stub(10)))
        await yieldUntil { [unowned self] in storage.saves.count == 1 }
        gate.open()
        await eventQueue.send(.messageEdited(.stub, nil, changeVersion: nil))
        sut.apply(.make(id: 3, position: .stub(20)))
        await yieldUntil { [unowned self] in storage.saves.count == 2 }

        XCTAssertEqual(storage.saves.map { $0.conversations.map(\.id) }, [[2], [3]])
        XCTAssertNil(storage.saves[0].state)
        XCTAssertEqual(storage.saves[1].state, loadedState)
    }

    // MARK: - Дельта позиций

    /// Кейс: список загружен; дельта вернула новую переписку и поднявшуюся известную, `hasNext: false`.
    /// Ожидание: запрос — `positionUpdatedAfter` с запасом 5 с; обе переписки встали по позиции, хвост сохранён;
    /// водяной знак позиции поднят до максимума дельты; запущена сверка изменений от сохранённого курсора.
    func test_delta_withoutNext_mergesAndStartsChangeSync() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        let lifted = Conversation.make(id: 2, position: .stub(30)).with(position: .stub(30), lastMessage: .make(id: 9, updatedAt: .stub(30)))
        conversationService.stubbedPages = [.success(page([.make(id: 3, position: .stub(40)), lifted]))]
        conversationService.stubbedChangePages = [.success(page([]))]

        await connect()
        await yieldUntil { [unowned self] in conversationService.changeRequests.count == 1 }

        XCTAssertEqual(sut.conversations.map(\.id), [3, 2, 1])
        XCTAssertEqual(conversationService.requests.map(\.filter), [
            .positionUpdatedAfter(ServerTime.stub.adding(milliseconds: -5000), offset: nil),
        ])
        XCTAssertEqual(conversationService.changeRequests.map(\.filter), [.changedAfter(10)])
        XCTAssertEqual(conversationService.changeRequests.last?.count, ConversationListService.changesPageSize)
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(40) }
        XCTAssertTrue(storage.replacements.isEmpty)
    }

    /// Кейс: дельта вернула полную страницу и `hasNext: true` — поднялось больше страницы.
    /// Ожидание: остальные локальные переписки инвалидированы — список и БД заменены страницей; следующая
    /// страница пойдёт без фильтра со сдвигом, равным размеру страницы; сверка информации не запускается.
    func test_delta_withNext_invalidatesTail() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        conversationService.stubbedPages = [
            .success(page([.make(id: 4, position: .stub(40)), .make(id: 3, position: .stub(30))], hasNext: true)),
            .success(page([])),
        ]

        await connect()
        sut.loadNextPageIfNeeded(currentConversationId: 3)
        await yieldUntil { [unowned self] in conversationService.requests.count == 2 }

        XCTAssertEqual(sut.conversations.map(\.id), [4, 3])
        XCTAssertEqual(conversationService.requests.last?.filter, .none(offset: 2))
        await yieldUntil { [unowned self] in storage.replacements.count == 1 }
        XCTAssertEqual(storage.replacements.first?.conversations.map(\.id), [4, 3])
        XCTAssertEqual(storage.replacements.first?.state.positionWatermark, .stub(40))
    }

    // MARK: - Сверка изменений

    /// Кейс: сверка вернула две страницы: на первой известная переписка с новым названием и неизвестная,
    /// на второй — ещё одна известная; `changeVersion` ответа последней страницы — 16.
    /// Ожидание: вторая страница запрошена с версией последней переписки первой; известные слиты, неизвестная
    /// отброшена; курсор — максимум версий последней страницы.
    func test_changeSync_pagesWithCursorAndDropsUnknown() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        let renamed = Conversation.make(id: 1, position: .stub(-10), readState: .make(version: 12)).with(name: "Новое", updatedInfoAt: .stub(10))
        let unknown = Conversation.make(id: 9, position: .stub(-500), readState: .make(version: 13))
        let second = Conversation.make(id: 2, position: .stub(-20), readState: .make(version: 15)).with(name: "Второе", updatedInfoAt: .stub(30))
        conversationService.stubbedPages = [.success(page([]))]
        conversationService.stubbedChangePages = [
            .success(page([renamed, unknown], hasNext: true, version: 13)),
            .success(page([second], version: 16)),
        ]

        await connect()
        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 16 }

        XCTAssertEqual(conversationService.changeRequests.map(\.filter), [.changedAfter(10), .changedAfter(13)])
        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
        XCTAssertEqual(sut.conversations.map(\.name), ["Новое", "Второе"])
    }

    /// Кейс: первая страница сверки — `hasNext: true`, а вторая не пришла (ошибка сети).
    /// Ожидание: страница слита, а курсор не сдвинулся — следующая синхронизация повторит сверку с него.
    func test_changeSync_failedPage_keepsCursor() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        conversationService.stubbedPages = [.success(page([]))]
        conversationService.stubbedChangePages = [
            .success(page([Conversation.make(id: 1, readState: .make(unread: 2, version: 12))], hasNext: true, version: 14)),
        ]

        await connect()
        await yieldUntil { [unowned self] in conversationService.changeRequests.count == 2 }
        await yieldTimes()

        XCTAssertEqual(sut.conversations.first?.readState.unreadCount, 2)
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 10)
    }

    /// Кейс: идёт сверка изменений (ждёт ответа второй страницы), пришёл новый `connected`.
    /// Ожидание: новая синхронизация прерывает сверку — ответ второй страницы не применяется.
    func test_changeSync_interruptedByNewSync() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        let late = Conversation.make(id: 1, readState: .make(version: 20)).with(name: "Опоздавшее", updatedInfoAt: .stub(99))
        conversationService.stubbedPages = [.success(page([])), .success(page([]))]
        conversationService.stubbedChangePages = [
            .success(page([.make(id: 9, readState: .make(version: 12))], hasNext: true, version: 12)),
            .success(page([late], version: 20)),
            .success(page([], version: 10)),
        ]
        var isGated = false
        conversationService.onRequest = { [unowned self] in
            // Только вторая страница первой сверки: запрос дельты второй синхронизации не задерживается.
            guard conversationService.changeRequests.count == 2, !isGated else { return }
            isGated = true
            await gate.wait()
        }
        await connect()
        await yieldUntil { gate.isWaiting }

        await connect()
        gate.open()
        await yieldUntil { [unowned self] in conversationService.changeRequests.count == 3 }
        await yieldTimes()

        XCTAssertEqual(sut.conversations.first?.name, Conversation.make(id: 1).name)
    }

    // MARK: - События

    /// Кейс: `received` по переписке из списка.
    /// Ожидание: переписка поднялась наверх с превью из события; водяной знак позиции поднят до `createdAt`.
    func test_received_knownConversation_liftsAndRaisesWatermark() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        let message = Message.make(id: 30, conversationId: 2, createdAt: .stub(100))

        await eventQueue.send(.received(message))

        XCTAssertEqual(sut.conversations.map(\.id), [2, 1])
        XCTAssertEqual(sut.conversations.first?.lastMessage, LastMessage(message: message))
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(100) }
    }

    /// Кейс: `received` по переписке, которой нет в списке.
    /// Ожидание: переписка загружена через `getBatch`, слита с событием и вставлена по сортировке.
    func test_received_unknownConversation_loadsBatchAndInserts() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 5, position: .stub(-1000))], notFoundIds: []))]
        let message = Message.make(id: 30, conversationId: 5, createdAt: .stub(100))

        await eventQueue.send(.received(message))

        XCTAssertEqual(conversationService.batchRequests, [[5]])
        XCTAssertEqual(sut.conversations.map(\.id), [5, 1])
        XCTAssertEqual(sut.conversations.first?.positionUpdatedAt, .stub(100))
    }

    /// Кейс: `received` по переписке, которой нет на сервере для пользователя (`notFoundIds`).
    /// Ожидание: ничего не вставлено, синхронизация не запускается.
    func test_received_notFound_skips() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [], notFoundIds: [5]))]

        await eventQueue.send(.received(.make(id: 30, conversationId: 5)))

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertTrue(eventQueue.leaseReasons.isEmpty)
    }

    /// Кейс: `getBatch` по событию упал; следом пришло событие по известной переписке с более поздним временем.
    /// Ожидание: водяной знак опущен под потолок — время пропущенного события — и следующим событием не поднимается
    /// выше; запланирована синхронизация; потолок записан в БД.
    func test_received_batchFailure_capsWatermarkAndSchedulesSync() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: ConversationListState(
            isLoaded: true, hasMorePages: false, positionWatermark: .stub(200), positionWatermarkCeiling: nil, syncedChangeVersion: 10
        ))
        conversationService.stubbedBatches = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await eventQueue.send(.received(.make(id: 30, conversationId: 5, createdAt: .stub(100))))
        await eventQueue.send(.received(.make(id: 31, conversationId: 1, createdAt: .stub(300))))

        await yieldUntil { [unowned self] in storage.lastState?.positionWatermarkCeiling == .stub(100) }
        XCTAssertEqual(storage.lastState?.positionWatermark, .stub(100))
        XCTAssertEqual(eventQueue.leaseReasons.map(String.init(describing:)), ["conversationList.sync"])
    }

    /// Кейс: после неудачного `getBatch` (потолок в БД) приложение перезапущено, синхронизация успешна.
    /// Ожидание: дельта запрошена от водяного знака не выше потолка; успешная дельта снимает потолок.
    func test_ceiling_survivesRestartAndIsClearedBySuccessfulDelta() async {
        await start(cache: [.make(id: 1)], state: ConversationListState(
            isLoaded: true, hasMorePages: false, positionWatermark: .stub(100), positionWatermarkCeiling: .stub(100), syncedChangeVersion: 10
        ))
        conversationService.stubbedPages = [.success(page([.make(id: 5, position: .stub(150))]))]

        await connect()

        XCTAssertEqual(conversationService.requests.first?.filter, .positionUpdatedAfter(ServerTime.stub.adding(milliseconds: 100 - 5000), offset: nil))
        XCTAssertEqual(sut.conversations.map(\.id), [5, 1])
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(150) }
        XCTAssertNil(storage.lastState?.positionWatermarkCeiling)
    }

    /// Кейс: `singleCreated` с версией на 1 больше курсора.
    /// Ожидание: переписка вставлена; водяной знак позиции поднят, курсор изменений — до версии события.
    func test_conversationCreated_raisesWatermarkAndCursor() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)

        await eventQueue.send(.conversationCreated(.make(id: 7, position: .stub(60), readState: .make(version: 11))))

        XCTAssertEqual(sut.conversations.map(\.id), [7, 1])
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(60) }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 11)
    }

    /// Кейс: `edited` с превью по известной переписке; `edited` с превью по неизвестной; `edited` без превью.
    /// Ожидание: известная получила новый текст; неизвестная не загружается; без превью ничего не меняется.
    func test_edited_updatesKnownOnly() async {
        let local = Conversation.make(id: 1).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [local], state: loadedState)
        let edited = Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(500))

        await eventQueue.send(.edited(edited))
        await eventQueue.send(.edited(.make(id: 40, conversationId: 9)))
        await eventQueue.send(.messageEdited(.make(id: 15, conversationId: 1, text: "Ещё правка"), nil, changeVersion: nil))

        XCTAssertEqual(sut.conversations.map(\.lastMessage?.text), ["Правка"])
        XCTAssertTrue(conversationService.batchRequests.isEmpty)
    }

    // MARK: - Изменения из REST

    /// Кейс: ответ `/messages/send` по переписке из списка.
    /// Ожидание: переписка поднялась наверх и записана в БД; водяной знак позиции не сдвинут.
    func test_applySentMessage_liftsWithoutWatermark() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)

        sut.applySentMessage(.make(id: 50, conversationId: 2, createdAt: .stub(500)), readInfo: nil)

        XCTAssertEqual(sut.conversations.map(\.id), [2, 1])
        await yieldUntil { [unowned self] in storage.saves.contains { $0.conversations.map(\.id) == [2] } }
        XCTAssertEqual(storage.lastState?.positionWatermark, .stub)
    }

    /// Кейс: три переписки; отправленное сообщение подняло нижнюю; затем пришла правка последнего сообщения
    /// средней (без смены позиции).
    /// Ожидание: индекс после одиночного перемещения верен — правка применена к нужной переписке на месте,
    /// порядок не изменился.
    func test_singleUpdate_afterLift_keepsIndexConsistent() async {
        let cache = [
            Conversation.make(id: 1).with(position: .stub(-10), lastMessage: .make(id: 15, text: "Привет!")),
            .make(id: 2, position: .stub(-20)),
            .make(id: 3, position: .stub(-30)),
        ]
        await start(cache: cache, state: loadedState)

        sut.applySentMessage(.make(id: 50, conversationId: 3, createdAt: .stub(500)), readInfo: nil)
        await eventQueue.send(.edited(Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(600))))

        XCTAssertEqual(sut.conversations.map(\.id), [3, 1, 2])
        XCTAssertEqual(sut.conversations.map(\.lastMessage?.text)[1], "Правка")
    }

    /// Кейс: ответ `/messages/send` по переписке, которой нет в списке.
    /// Ожидание: переписка загружена через `getBatch` и вставлена с отправленным сообщением.
    func test_applySentMessage_unknownConversation_loadsBatch() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 5, position: .stub(-900))], notFoundIds: []))]

        sut.applySentMessage(.make(id: 50, conversationId: 5, createdAt: .stub(500)), readInfo: nil)

        await yieldUntil { [unowned self] in sut.conversations.map(\.id) == [5, 1] }
        XCTAssertEqual(sut.conversations.first?.lastMessage?.messageId, 50)
    }

    /// Кейс: идёт полная загрузка; в это время пришёл ответ `/messages/send`, а страница собрана раньше отправки.
    /// Ожидание: после замены списка страницей отправленное сообщение осталось в превью и переписка — наверху.
    func test_applySentMessage_duringFullLoad_survivesReplacement() async {
        await start(cache: [.make(id: 2, position: .stub(5))])
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 1, position: .stub(10)), .make(id: 2, position: .stub(5))]))]
        conversationService.onRequest = { await gate.wait() }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }

        sut.applySentMessage(.make(id: 50, conversationId: 2, createdAt: .stub(500)), readInfo: nil)
        gate.open()
        await yieldUntil { [unowned self] in !sut.isSyncing }

        XCTAssertEqual(sut.conversations.map(\.id), [2, 1])
        XCTAssertEqual(sut.conversations.first?.lastMessage?.messageId, 50)
    }

    /// Кейс: две переписки; ответ `/messages/edit` по последнему сообщению нижней — с новым превью.
    /// Ожидание: превью обновлено на месте, порядок не изменился, изменение записано в БД.
    func test_applyEditedMessage_updatesPreviewWithoutMoving() async {
        let edited = Conversation.make(id: 2).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [.make(id: 1, position: .stub(10)), edited], state: loadedState)
        let message = Message.make(id: 15, conversationId: 2, text: "Правка").withUpdatedAt(.stub(500))

        sut.applyEditedMessage(message, lastMessage: LastMessage(message: message))

        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
        XCTAssertEqual(sut.conversations.last?.lastMessage?.text, "Правка")
        await yieldUntil { [unowned self] in storage.saves.contains { $0.conversations.map(\.id) == [2] } }
    }

    /// Кейс: ответ `/messages/edit` без превью; ответ с превью по переписке, которой нет в списке.
    /// Ожидание: список не меняется, переписка не загружается.
    func test_applyEditedMessage_withoutPreviewOrUnknown_doesNothing() async {
        let local = Conversation.make(id: 1).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [local], state: loadedState)
        let unknown = Message.make(id: 40, conversationId: 9).withUpdatedAt(.stub(500))

        sut.applyEditedMessage(Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(500)), lastMessage: nil)
        sut.applyEditedMessage(unknown, lastMessage: LastMessage(message: unknown))

        await yieldTimes()
        XCTAssertEqual(sut.conversations, [local])
        XCTAssertTrue(conversationService.batchRequests.isEmpty)
    }

    /// Кейс: правка применена по ответу, затем пришло эхо-событие `edited` с той же версией.
    /// Ожидание: событие ничего не меняет — превью прежнее, переписка в БД повторно не пишется.
    func test_applyEditedMessage_thenSameEvent_isIdempotent() async {
        let local = Conversation.make(id: 1).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [local], state: loadedState)
        let message = Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(500))
        sut.applyEditedMessage(message, lastMessage: LastMessage(message: message))
        await yieldTimes()
        let savesBefore = storage.saves.count
        let conversationsBefore = sut.conversations

        await eventQueue.send(.edited(message))

        await yieldTimes()
        XCTAssertEqual(sut.conversations, conversationsBefore)
        XCTAssertTrue(storage.saves.dropFirst(savesBefore).allSatisfy { $0.conversations.isEmpty })
    }

    /// Кейс: идёт полная загрузка; в это время пришёл ответ `/messages/edit`, а страница собрана раньше правки.
    /// Ожидание: после замены списка страницей превью осталось отредактированным.
    func test_applyEditedMessage_duringFullLoad_survivesReplacement() async {
        let local = Conversation.make(id: 1).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [local])
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([local]))]
        conversationService.onRequest = { await gate.wait() }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }
        let message = Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(500))

        sut.applyEditedMessage(message, lastMessage: LastMessage(message: message))
        gate.open()
        await yieldUntil { [unowned self] in !sut.isSyncing }

        XCTAssertEqual(sut.conversations.first?.lastMessage?.text, "Правка")
    }

    /// Кейс: созданная переписка применена (`createSingle`).
    /// Ожидание: она встала по сортировке; водяные знаки не двигаются.
    func test_apply_insertsWithoutWatermarks() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)

        sut.apply(.make(id: 8, position: .stub(70)))

        XCTAssertEqual(sut.conversations.map(\.id), [8, 1])
        await yieldUntil { [unowned self] in storage.saves.contains { $0.conversations.map(\.id) == [8] } }
        XCTAssertEqual(storage.lastState?.positionWatermark, .stub)
    }

    // MARK: - Истёкшая аренда

    /// Кейс: идёт полная загрузка; аренду сняли сторожевым таймаутом, очередь применила событие; затем пришла
    /// страница, собранная раньше события.
    /// Ожидание: страница слита, а не заменила список: переписка из события осталась, её позиция не откатилась;
    /// водяные знаки не двигались.
    func test_expiredLease_mergesInsteadOfReplacing() async {
        await start()
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 1, position: .stub(10)), .make(id: 2, position: .stub(5))]))]
        conversationService.onRequest = { await gate.wait() }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }
        eventQueue.expire(eventQueue.issuedLeases[0])
        await eventQueue.send(.conversationCreated(.make(id: 3, position: .stub(50))))

        gate.open()
        await yieldUntil { [unowned self] in !sut.isSyncing }

        XCTAssertEqual(sut.conversations.map(\.id), [3, 1, 2])
        XCTAssertTrue(storage.replacements.isEmpty)
        XCTAssertNil(storage.lastState?.positionWatermark)
    }

    // MARK: - Пагинация

    /// Кейс: показана одна из последних переписок; следующая страница содержит повтор и новую переписку.
    /// Ожидание: запрос без фильтра со сдвигом по числу серверных переписок; повтор слит, новая дописана;
    /// сдвиг увеличен на размер ответа; `hasMorePages` — из ответа.
    func test_nextPage_mergesDuplicatesAndAdvancesOffset() async {
        await start(cache: [.make(id: 3, position: .stub(30)), .make(id: 2, position: .stub(20))], state: loadedState)
        conversationService.stubbedPages = [
            .success(page([.make(id: 2, position: .stub(20)), .make(id: 1, position: .stub(10))], hasNext: true)),
            .success(page([])),
        ]

        sut.loadNextPageIfNeeded(currentConversationId: 2)
        await yieldUntil { [unowned self] in !sut.isLoadingNextPage && conversationService.requests.count == 1 }
        sut.loadNextPageIfNeeded(currentConversationId: 1)
        await yieldUntil { [unowned self] in conversationService.requests.count == 2 }

        XCTAssertEqual(sut.conversations.map(\.id), [3, 2, 1])
        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: 2), .none(offset: 4)])
    }

    /// Кейс: страниц больше нет, либо идёт стартовая синхронизация.
    /// Ожидание: следующая страница не запрашивается.
    func test_nextPage_withoutMorePagesOrWhileSyncing_doesNotLoad() async {
        await start(cache: [.make(id: 1)], state: ConversationListState(isLoaded: true, hasMorePages: false, positionWatermark: .stub, positionWatermarkCeiling: nil, syncedChangeVersion: 10))
        sut.loadNextPageIfNeeded(currentConversationId: 1)

        let gate = Gate()
        conversationService.onRequest = { await gate.wait() }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }
        sut.loadNextPageIfNeeded(currentConversationId: 1)

        XCTAssertEqual(conversationService.requests.count, 1)
        gate.open()
    }

    /// Кейс: последняя строка показана, пока идёт стартовая синхронизация; дельта список не изменила.
    /// Ожидание: во время синхронизации страница не запрашивается, а после неё — запрашивается без новой прокрутки.
    func test_nextPage_requestedDuringSync_loadsAfterSync() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([])), .success(page([.make(id: 2, position: .stub(-10))]))]
        conversationService.onRequest = { [unowned self] in
            if conversationService.requests.count == 1 { await gate.wait() }
        }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }

        sut.loadNextPageIfNeeded(currentConversationId: 1)
        XCTAssertEqual(conversationService.requests.count, 1)
        gate.open()
        await yieldUntil { [unowned self] in conversationService.requests.count == 2 && !sut.isLoadingNextPage }

        XCTAssertEqual(conversationService.requests.last?.filter, .none(offset: 1))
        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
    }

    /// Кейс: в списке переписки 3, 2, 1; следующая страница несёт новую переписку, повтор известной с более поздней
    /// позицией (поднялась, пока листали) и две версии одной новой переписки.
    /// Ожидание: страница слита за один проход — порядок по позиции, у повтора одной переписки взята более поздняя
    /// версия; в БД каждая изменённая переписка записана один раз.
    func test_nextPage_batchMerge_sortsOnceAndPersistsEachOnce() async {
        let cache = [
            Conversation.make(id: 3, position: .stub(30)),
            Conversation.make(id: 2, position: .stub(20)),
            Conversation.make(id: 1, position: .stub(10)),
        ]
        await start(cache: cache, state: loadedState)
        let lifted = Conversation.make(id: 1, position: .stub(50)).with(position: .stub(50), lastMessage: .make(id: 7, updatedAt: .stub(50)))
        let newer = Conversation.make(id: 5, position: .stub(-5)).with(position: .stub(-5), lastMessage: .make(id: 8, updatedAt: .stub(-5)))
        let nextPage = [
            Conversation.make(id: 4, position: .stub(-1)),
            lifted,
            Conversation.make(id: 5, position: .stub(-9)),
            newer,
        ]
        conversationService.stubbedPages = [.success(page(nextPage, hasNext: true))]

        sut.loadNextPageIfNeeded(currentConversationId: 1)
        await yieldUntil { [unowned self] in !sut.isLoadingNextPage && !storage.saves.isEmpty }

        XCTAssertEqual(sut.conversations.map(\.id), [1, 3, 2, 4, 5])
        XCTAssertEqual(sut.conversations.first { $0.id == 5 }?.positionUpdatedAt, .stub(-5))
        XCTAssertEqual(storage.saves.last?.conversations.map(\.id), [4, 1, 5])
    }

    /// Кейс: дельта подняла несколько известных переписок и принесла новую; затем пришло событие по одной из них.
    /// Ожидание: индекс после пачки верен — событие слилось с нужной перепиской, без `getBatch` и без дубликатов.
    func test_delta_batchMerge_keepsIndexConsistent() async {
        let cache = [
            Conversation.make(id: 1, position: .stub(-10)),
            Conversation.make(id: 2, position: .stub(-20)),
            Conversation.make(id: 3, position: .stub(-30)),
        ]
        await start(cache: cache, state: loadedState)
        conversationService.stubbedPages = [.success(page([
            Conversation.make(id: 3, position: .stub(40)).with(position: .stub(40), lastMessage: .make(id: 30, updatedAt: .stub(40))),
            Conversation.make(id: 4, position: .stub(35)),
            Conversation.make(id: 2, position: .stub(30)).with(position: .stub(30), lastMessage: .make(id: 20, updatedAt: .stub(30))),
        ]))]
        await connect()
        XCTAssertEqual(sut.conversations.map(\.id), [3, 4, 2, 1])

        await eventQueue.send(.received(Message.make(id: 31, conversationId: 1, createdAt: .stub(100))))

        XCTAssertEqual(sut.conversations.map(\.id), [1, 3, 4, 2])
        XCTAssertEqual(sut.conversations.first?.lastMessage?.messageId, 31)
        XCTAssertTrue(conversationService.batchRequests.isEmpty)
    }

    // MARK: - Курсор изменений и общий счётчик

    /// Кейс: курсор 10; `received` с версией 12 (пропуск 11), затем `read` с версией 11.
    /// Ожидание: после пропуска курсор стоит на 10, а общий счётчик уже из события; когда пришла 11 — курсор
    /// растёт сразу до 12.
    func test_events_advanceCursorByContinuity() async {
        await start(cache: [.make(id: 1)], state: loadedState)

        await eventQueue.send(.received(.make(id: 30, conversationId: 1, createdAt: .stub(100)), readInfo: .make(conversationId: 1, unread: 1, total: 4, version: 12)))
        await yieldUntil { [unowned self] in storage.lastState?.totalUnreadCount == 4 }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 10)

        await eventQueue.send(.conversationRead(.make(conversationId: 2, total: 4, version: 11)))

        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 12 }
        XCTAssertEqual(sut.totalUnreadCount, 4)
    }

    /// Кейс: `read` с версией 15 и общим счётчиком 3, затем запоздавшее `received` с версией 14 и счётчиком 9.
    /// Ожидание: общий счётчик сливается по своей версии — остаётся 3.
    func test_totalUnread_olderVersionIgnored() async {
        await start(cache: [.make(id: 1)], state: loadedState)

        await eventQueue.send(.conversationRead(.make(conversationId: 1, total: 3, version: 15)))
        await eventQueue.send(.received(.make(id: 30, conversationId: 1, createdAt: .stub(100)), readInfo: .make(conversationId: 1, unread: 1, total: 9, version: 14)))

        XCTAssertEqual(sut.totalUnreadCount, 3)
    }

    /// Кейс: `read` по переписке, которой нет в списке.
    /// Ожидание: общий счётчик применён; переписка не загружается и в список не попадает.
    func test_conversationRead_unknownConversation_updatesTotalOnly() async {
        await start(cache: [.make(id: 1)], state: loadedState)

        await eventQueue.send(.conversationRead(.make(conversationId: 99, total: 7, version: 11)))

        XCTAssertEqual(sut.totalUnreadCount, 7)
        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertTrue(conversationService.batchRequests.isEmpty)
    }

    /// Кейс: ответ на отправку несёт прочтение с версией 11 (на 1 больше курсора).
    /// Ожидание: прочтение переписки и общий счётчик применены, курсор не двигается — то же придёт событием.
    func test_applySentMessage_readInfo_appliesWithoutCursor() async {
        await start(cache: [.make(id: 1, readState: .make(unread: 2, lastRead: 10, version: 10))], state: loadedState)

        sut.applySentMessage(.make(id: 50, conversationId: 1, createdAt: .stub(500)), readInfo: .make(conversationId: 1, lastRead: 50, total: 1, version: 11))

        XCTAssertEqual(sut.readState(conversationId: 1), .make(unread: 0, lastRead: 50, version: 11))
        XCTAssertEqual(sut.totalUnreadCount, 1)
        await yieldUntil { [unowned self] in storage.lastState?.totalUnreadCount == 1 }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 10)
    }

    /// Кейс: список загружен (есть водяной знак позиции), но курсора изменений нет — данные до миграции.
    /// Ожидание: синхронизация — полная загрузка, а не дельта; курсор — из ответа.
    func test_missingCursor_loadsFirstPage() async {
        await start(cache: [.make(id: 1)], state: ConversationListState(isLoaded: true, hasMorePages: false, positionWatermark: .stub))
        conversationService.stubbedPages = [.success(page([.make(id: 1)], version: 42))]

        await connect()

        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: nil)])
        await yieldUntil { [unowned self] in storage.replacements.count == 1 }
        XCTAssertEqual(storage.replacements.first?.state.syncedChangeVersion, 42)
    }

    // MARK: - Отметка прочтения

    /// Кейс: переписка с 2 непрочитанными, общий счётчик 5; `markRead` до id 20, ответ задержан, затем пришёл.
    /// Ожидание: сразу — переписка прочитана для показа, общий счётчик без её непрочитанных, подтверждённое прочтение
    /// прежнее; после ответа — подтверждённое прочтение из ответа, отметка снята; запрос один.
    func test_markRead_optimisticThenConfirmed() async {
        await startWithUnread()
        let gate = Gate()
        conversationService.onMarkRead = { await gate.wait() }
        conversationService.stubbedReadInfos = [.success(.make(conversationId: 1, lastRead: 20, total: 3, version: 11))]

        sut.markRead(conversationId: 1, messageId: 20)
        await yieldUntil { gate.isWaiting }

        XCTAssertEqual(sut.unreadCount(conversationId: 1), 0)
        XCTAssertEqual(sut.totalUnreadCount, 3)
        XCTAssertEqual(sut.readState(conversationId: 1)?.unreadCount, 2)
        gate.open()
        await yieldUntil { [unowned self] in sut.readState(conversationId: 1)?.lastReadMessageId == 20 }
        XCTAssertEqual(sut.unreadCount(conversationId: 1), 0)
        XCTAssertEqual(sut.totalUnreadCount, 3)
        XCTAssertEqual(conversationService.markReadRequests.map(\.messageId), [20])
    }

    /// Кейс: `markRead` до 20 в полёте; за это время — отметки до 21 и 22.
    /// Ожидание: пока первый запрос в полёте, второго нет; после ответа уходит только последняя отметка — до 22.
    func test_markRead_whileInFlight_sendsLatestAfterResponse() async {
        await startWithUnread()
        let gate = Gate()
        conversationService.onMarkRead = { [unowned self] in
            if conversationService.markReadRequests.count == 1 { await gate.wait() }
        }
        conversationService.stubbedReadInfos = [
            .success(.make(conversationId: 1, lastRead: 20, total: 3, version: 11)),
            .success(.make(conversationId: 1, lastRead: 22, total: 3, version: 12)),
        ]

        sut.markRead(conversationId: 1, messageId: 20)
        await yieldUntil { gate.isWaiting }
        sut.markRead(conversationId: 1, messageId: 21)
        sut.markRead(conversationId: 1, messageId: 22)
        XCTAssertEqual(conversationService.markReadRequests.map(\.messageId), [20])
        gate.open()

        await yieldUntil { [unowned self] in sut.readState(conversationId: 1)?.lastReadMessageId == 22 }
        XCTAssertEqual(conversationService.markReadRequests.map(\.messageId), [20, 22])
    }

    /// Кейс: `markRead` упал с ошибкой сети; затем экран снова отмечает то же сообщение.
    /// Ожидание: после ошибки переписка снова непрочитана для показа, общий счётчик прежний; повторная отметка
    /// уходит на сервер.
    func test_markRead_failure_restoresUnreadAndAllowsRetry() async {
        await startWithUnread()
        conversationService.stubbedReadInfos = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        sut.markRead(conversationId: 1, messageId: 20)
        await yieldUntil { [unowned self] in sut.unreadCount(conversationId: 1) == 2 && conversationService.markReadRequests.count == 1 }
        XCTAssertEqual(sut.totalUnreadCount, 5)

        sut.markRead(conversationId: 1, messageId: 20)

        await yieldUntil { [unowned self] in conversationService.markReadRequests.count == 2 }
        XCTAssertEqual(conversationService.markReadRequests.map(\.messageId), [20, 20])
    }

    /// Кейс: `markRead` до сообщения не новее подтверждённого указателя (10).
    /// Ожидание: запроса нет, счётчики не меняются.
    func test_markRead_notAboveConfirmed_skipped() async {
        await startWithUnread()

        sut.markRead(conversationId: 1, messageId: 10)

        XCTAssertTrue(conversationService.markReadRequests.isEmpty)
        XCTAssertEqual(sut.unreadCount(conversationId: 1), 2)
    }

    /// Кейс: отметка до 20 в полёте; пришло `received`, созданное сервером раньше неё: указатель 10, 3 непрочитанных.
    /// Ожидание: подтверждённое прочтение обновлено, но для показа переписка прочитана — отметка не снята, счётчик
    /// не «мигает».
    func test_markRead_lowerPointerEvent_keepsOptimistic() async {
        await startWithUnread()
        let gate = Gate()
        conversationService.onMarkRead = { await gate.wait() }

        sut.markRead(conversationId: 1, messageId: 20)
        await yieldUntil { gate.isWaiting }
        await eventQueue.send(.received(.make(id: 19, conversationId: 1, createdAt: .stub(100)), readInfo: .make(conversationId: 1, lastRead: 10, unread: 3, total: 6, version: 11)))

        XCTAssertEqual(sut.readState(conversationId: 1)?.unreadCount, 3)
        XCTAssertEqual(sut.unreadCount(conversationId: 1), 0)
        gate.open()
    }

    /// Кейс: переписки 99 нет в списке; `markRead` до id 40, ответ задержан, затем пришёл; затем та же отметка снова.
    /// Ожидание: пока запрос в полёте — переписка прочитана для показа; после ответа — подтверждённое прочтение
    /// из ответа, переписка в список не попала; повторная отметка на сервер не уходит.
    func test_markRead_unlistedConversation_showsReadAndSkipsRepeat() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        conversationService.onMarkRead = { await gate.wait() }
        conversationService.stubbedReadInfos = [.success(.make(conversationId: 99, lastRead: 40, total: 2, version: 11))]

        sut.markRead(conversationId: 99, messageId: 40)
        await yieldUntil { gate.isWaiting }

        XCTAssertNil(sut.readState(conversationId: 99))
        XCTAssertEqual(sut.unreadCount(conversationId: 99), 0)
        gate.open()
        await yieldUntil { [unowned self] in sut.readState(conversationId: 99) != nil }
        XCTAssertEqual(sut.readState(conversationId: 99), .make(unread: 0, lastRead: 40, version: 11))
        XCTAssertEqual(sut.unreadCount(conversationId: 99), 0)
        XCTAssertEqual(sut.conversations.map(\.id), [1])
        sut.markRead(conversationId: 99, messageId: 40)
        XCTAssertEqual(conversationService.markReadRequests.map(\.messageId), [40])
    }

    /// Кейс: по переписке 99 вне списка пришло `read` с версией 12 и 3 непрочитанными, затем — с версией 11 и 0.
    /// Ожидание: прочтение и счётчик для показа — из более новой версии (3 непрочитанных); старая версия не применена.
    func test_conversationRead_unlistedConversation_keepsNewestReadState() async {
        await start(cache: [.make(id: 1)], state: loadedState)

        await eventQueue.send(.conversationRead(.make(conversationId: 99, lastRead: 30, unread: 3, total: 3, version: 12)))
        await eventQueue.send(.conversationRead(.make(conversationId: 99, lastRead: 25, total: 3, version: 11)))

        XCTAssertEqual(sut.readState(conversationId: 99), .make(unread: 3, lastRead: 30, version: 12))
        XCTAssertEqual(sut.unreadCount(conversationId: 99), 3)
    }

    // MARK: - Pull-to-refresh

    /// Кейс: pull-to-refresh при загруженном списке.
    /// Ожидание: полная загрузка под арендой заменила список и БД — переписка, пропавшая с сервера, исчезла.
    func test_refresh_replacesListUnderLease() async throws {
        await start(cache: [.make(id: 1), .make(id: 9, position: .stub(-99))], state: loadedState)
        conversationService.stubbedPages = [.success(page([.make(id: 1)]))]

        try await sut.refresh()

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: nil)])
        XCTAssertEqual(eventQueue.leaseReasons.map(String.init(describing:)), ["conversationList.refresh"])
        XCTAssertEqual(eventQueue.activeLeaseCount, 0)
        XCTAssertFalse(sut.isSyncing)
    }

    /// Кейс: идёт pull-to-refresh, пришёл `connected`.
    /// Ожидание: обновление прервано и завершается `CancellationError`; список обновила синхронизация.
    func test_refresh_interruptedBySync_throwsCancellation() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 7)])), .success(page([.make(id: 2, position: .stub(5))]))]
        conversationService.onRequest = { [unowned self] in
            if conversationService.requests.count == 1 { await gate.wait() }
        }
        let refresh = Task { [sut] in try await sut!.refresh() }
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.connected)
        await yieldUntil { [unowned self] in !sut.isSyncing && conversationService.requests.count >= 2 }
        gate.open()
        let result = await refresh.result

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(sut.conversations.map(\.id), [2, 1])
    }

    // MARK: - Выход

    /// Кейс: выход, пока идёт синхронизация.
    /// Ожидание: выход дожидается задачи; список и состояние очищены; ответ, пришедший после, ничего не пишет.
    func test_willLogout_cancelsAndClears() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        conversationService.stubbedPages = [.success(page([.make(id: 2, position: .stub(10))]))]
        conversationService.onRequest = { await gate.wait() }
        await eventQueue.send(.connected)
        await yieldUntil { gate.isWaiting }
        let savesBefore = storage.saves.count

        let logout = Task { [sut] in await sut!.authServiceWillLogout() }
        await yieldTimes()
        gate.open()
        await logout.value

        XCTAssertTrue(sut.conversations.isEmpty)
        XCTAssertFalse(sut.isSyncing)
        XCTAssertFalse(sut.hasMorePages)
        XCTAssertEqual(storage.saves.count, savesBefore)
        XCTAssertTrue(storage.replacements.isEmpty)
    }

    /// Кейс: в кэше группа, последнее сообщение которой отправил пользователь 7, и личная переписка с собеседником 2.
    /// Ожидание: при чтении кэша загружаются и собеседник, и отправитель превью группы.
    func test_start_loadsGroupPreviewSenders() async {
        let group = Conversation.make(id: 5).with(position: .stub, lastMessage: LastMessage(messageId: 3, senderId: 7, type: .text, text: "Привет", updatedAt: .stub))
        await start(cache: [group, Conversation.singleStub], state: loadedState)

        await yieldUntil { [unowned self] in !userCache.loadRequests.isEmpty }
        XCTAssertEqual(userCache.loadRequests.first.map(Set.init), [2, 7])
    }

    // MARK: - Helpers

    /// Создаёт сервис над моками теста.
    private func makeSUT() -> ConversationListService {
        ConversationListService(conversationService: conversationService, storage: storage, eventQueue: eventQueue, userCache: userCache)
    }

    /// Запускает сервис над перепиской 1 с 2 непрочитанными (указатель 10, версия 10) и общим счётчиком 5.
    private func startWithUnread() async {
        var state = loadedState
        state.totalUnreadCount = 5
        state.totalUnreadVersion = 10
        await start(cache: [.make(id: 1, readState: .make(unread: 2, lastRead: 10, version: 10))], state: state)
    }

    /// Запускает сервис над заданным кэшем и дожидается чтения кэша.
    /// - Parameters:
    ///   - cache: переписки в БД.
    ///   - state: состояние синхронизации в БД.
    private func start(cache: [Conversation] = [], state: ConversationListState = ConversationListState()) async {
        storage.stubbedList = .success((cache, state))
        sut.start()
        // Обработчик любого события, кроме `connected`, ждёт чтения кэша; `edited` без превью ничего не меняет.
        await eventQueue.send(.messageEdited(.stub, nil, changeVersion: nil))
    }

    /// Доставляет `connected` и ждёт окончания основной фазы синхронизации.
    private func connect(file: StaticString = #filePath, line: UInt = #line) async {
        await eventQueue.send(.connected)
        await yieldUntil(file: file, line: line) { [unowned self] in !sut.isSyncing && eventQueue.activeLeaseCount == 0 }
    }

    /// Страница списка.
    /// - Parameters:
    ///   - conversations: переписки.
    ///   - hasNext: есть ли продолжение.
    ///   - totalUnread: общий счётчик ответа.
    ///   - version: `changeVersion` ответа; по умолчанию — 10, как курсор `loadedState`.
    private func page(_ conversations: [Conversation], hasNext: Bool = false, totalUnread: Int = 0, version: Int = 10) -> ConversationsPage {
        ConversationsPage(conversations: conversations, hasNext: hasNext, totalUnreadCount: totalUnread, changeVersion: version)
    }
}

private extension Message {
    /// Копия сообщения, отредактированная в указанное время.
    /// - Parameter updatedAt: время правки.
    func withUpdatedAt(_ updatedAt: ServerTime) -> Message {
        Message(
            messageId: messageId, clientId: clientId, conversationId: conversationId, blockId: blockId, senderId: senderId,
            type: type, text: text, isEdited: true, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
