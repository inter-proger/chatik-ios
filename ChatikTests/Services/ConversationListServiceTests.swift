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

    /// Состояние загруженного списка: водяные знаки позиции и информации — `ServerTime.stub`.
    private let loadedState = ConversationListState(
        isLoaded: true,
        hasMorePages: true,
        positionWatermark: .stub,
        positionWatermarkCeiling: nil,
        infoWatermark: .stub
    )

    /// Состояние загруженного списка без водяного знака информации: после дельты сверка информации не запускается.
    private let noInfoState = ConversationListState(
        isLoaded: true,
        hasMorePages: true,
        positionWatermark: .stub,
        positionWatermarkCeiling: nil,
        infoWatermark: nil
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
    /// Ожидание: первая страница без фильтра заменила список и БД; водяные знаки — максимумы страницы;
    /// индикатор и аренда сняты.
    func test_connected_notLoaded_loadsFirstPage() async {
        await start()
        let newest = Conversation.make(id: 1, position: .stub(50), updatedInfoAt: .stub(5))
        let older = Conversation.make(id: 2, position: .stub(10), updatedInfoAt: .stub(70))
        conversationService.stubbedPages = [.success(page([newest, older], hasNext: true))]

        await connect()

        XCTAssertEqual(conversationService.requests.map(\.filter), [.none(offset: nil)])
        XCTAssertEqual(conversationService.requests.first?.count, ConversationListService.pageSize)
        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
        XCTAssertTrue(sut.hasMorePages)
        await yieldUntil { [unowned self] in storage.replacements.count == 1 }
        XCTAssertEqual(storage.replacements.first?.state, ConversationListState(
            isLoaded: true, hasMorePages: true, positionWatermark: .stub(50), positionWatermarkCeiling: nil, infoWatermark: .stub(70)
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
        storage.stubbedList = .success(([.make(id: 1)], noInfoState))
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
        await start(cache: [.make(id: 1)], state: noInfoState)
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
        await eventQueue.send(.messageEdited(.stub, nil))
        sut.apply(.make(id: 3, position: .stub(20)))
        await yieldUntil { [unowned self] in storage.saves.count == 2 }

        XCTAssertEqual(storage.saves.map { $0.conversations.map(\.id) }, [[2], [3]])
        XCTAssertNil(storage.saves[0].state)
        XCTAssertEqual(storage.saves[1].state, loadedState)
    }

    // MARK: - Дельта позиций

    /// Кейс: список загружен; дельта вернула новую переписку и поднявшуюся известную, `hasNext: false`.
    /// Ожидание: запрос — `positionUpdatedAfter` с запасом 5 с; обе переписки встали по позиции, хвост сохранён;
    /// водяной знак позиции поднят до максимума дельты; запущена сверка информации от сохранённого водяного знака.
    func test_delta_withoutNext_mergesAndStartsInfoSync() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        let lifted = Conversation.make(id: 2, position: .stub(30)).with(position: .stub(30), lastMessage: .make(id: 9, updatedAt: .stub(30)))
        conversationService.stubbedPages = [
            .success(page([.make(id: 3, position: .stub(40)), lifted])),
            .success(page([])),
        ]

        await connect()
        await yieldUntil { [unowned self] in conversationService.requests.count == 2 }

        XCTAssertEqual(sut.conversations.map(\.id), [3, 2, 1])
        XCTAssertEqual(conversationService.requests.map(\.filter), [
            .positionUpdatedAfter(ServerTime.stub.adding(milliseconds: -5000), offset: nil),
            .updatedInfoAfter(ServerTime.stub.adding(milliseconds: -5000), afterId: nil),
        ])
        XCTAssertEqual(conversationService.requests.last?.count, ConversationListService.infoPageSize)
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

    // MARK: - Сверка информации

    /// Кейс: сверка вернула две страницы: на первой известная переписка с новым названием и неизвестная,
    /// на второй — ещё одна известная.
    /// Ожидание: страницы запрошены курсором последней переписки; известные слиты, неизвестная отброшена;
    /// водяной знак информации — `updatedInfoAt` последней переписки последней страницы.
    func test_infoSync_pagesWithCursorAndDropsUnknown() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)
        let renamed = Conversation.make(id: 1, position: .stub(-10)).with(name: "Новое", updatedInfoAt: .stub(10))
        let unknown = Conversation.make(id: 9, position: .stub(-500), updatedInfoAt: .stub(20))
        let second = Conversation.make(id: 2, position: .stub(-20)).with(name: "Второе", updatedInfoAt: .stub(30))
        conversationService.stubbedPages = [
            .success(page([])),
            .success(page([renamed, unknown], hasNext: true)),
            .success(page([second])),
        ]

        await connect()
        await yieldUntil { [unowned self] in storage.lastState?.infoWatermark == .stub(30) }

        XCTAssertEqual(conversationService.requests.dropFirst().map(\.filter), [
            .updatedInfoAfter(ServerTime.stub.adding(milliseconds: -5000), afterId: nil),
            .updatedInfoAfter(.stub(20), afterId: 9),
        ])
        XCTAssertEqual(sut.conversations.map(\.id), [1, 2])
        XCTAssertEqual(sut.conversations.map(\.name), ["Новое", "Второе"])
    }

    /// Кейс: идёт сверка информации (ждёт ответа второй страницы), пришёл новый `connected`.
    /// Ожидание: новая синхронизация прерывает сверку — ответ второй страницы не применяется.
    func test_infoSync_interruptedByNewSync() async {
        await start(cache: [.make(id: 1)], state: loadedState)
        let gate = Gate()
        let late = Conversation.make(id: 1).with(name: "Опоздавшее", updatedInfoAt: .stub(99))
        conversationService.stubbedPages = [
            .success(page([])),
            .success(page([.make(id: 9, updatedInfoAt: .stub(5))], hasNext: true)),
            .success(page([late])),
            .success(page([])),
            .success(page([])),
        ]
        conversationService.onRequest = { [unowned self] in
            if conversationService.requests.count == 3 { await gate.wait() }
        }
        await connect()
        await yieldUntil { gate.isWaiting }

        await connect()
        gate.open()
        await yieldUntil { [unowned self] in conversationService.requests.count == 5 }
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
            isLoaded: true, hasMorePages: false, positionWatermark: .stub(200), positionWatermarkCeiling: nil, infoWatermark: .stub
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
            isLoaded: true, hasMorePages: false, positionWatermark: .stub(100), positionWatermarkCeiling: .stub(100), infoWatermark: nil
        ))
        conversationService.stubbedPages = [.success(page([.make(id: 5, position: .stub(150))]))]

        await connect()

        XCTAssertEqual(conversationService.requests.first?.filter, .positionUpdatedAfter(ServerTime.stub.adding(milliseconds: 100 - 5000), offset: nil))
        XCTAssertEqual(sut.conversations.map(\.id), [5, 1])
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(150) }
        XCTAssertNil(storage.lastState?.positionWatermarkCeiling)
    }

    /// Кейс: `singleCreated` с информацией новее водяного знака.
    /// Ожидание: переписка вставлена; водяной знак позиции поднят, информации — нет: правки, которые находит
    /// только сверка, не должны пропасть.
    func test_conversationCreated_raisesOnlyPositionWatermark() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)

        await eventQueue.send(.conversationCreated(.make(id: 7, position: .stub(60), updatedInfoAt: .stub(60))))

        XCTAssertEqual(sut.conversations.map(\.id), [7, 1])
        await yieldUntil { [unowned self] in storage.lastState?.positionWatermark == .stub(60) }
        XCTAssertEqual(storage.lastState?.infoWatermark, .stub)
    }

    /// Кейс: `edited` с превью по известной переписке; `edited` с превью по неизвестной; `edited` без превью.
    /// Ожидание: известная получила новый текст; неизвестная не загружается; без превью ничего не меняется.
    func test_edited_updatesKnownOnly() async {
        let local = Conversation.make(id: 1).with(position: .stub, lastMessage: .make(id: 15, text: "Привет!"))
        await start(cache: [local], state: loadedState)
        let edited = Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(500))

        await eventQueue.send(.edited(edited))
        await eventQueue.send(.edited(.make(id: 40, conversationId: 9)))
        await eventQueue.send(.messageEdited(.make(id: 15, conversationId: 1, text: "Ещё правка"), nil))

        XCTAssertEqual(sut.conversations.map(\.lastMessage?.text), ["Правка"])
        XCTAssertTrue(conversationService.batchRequests.isEmpty)
    }

    // MARK: - Изменения из REST

    /// Кейс: ответ `/messages/send` по переписке из списка.
    /// Ожидание: переписка поднялась наверх и записана в БД; водяной знак позиции не сдвинут.
    func test_applySentMessage_liftsWithoutWatermark() async {
        await start(cache: [.make(id: 1, position: .stub(-10)), .make(id: 2, position: .stub(-20))], state: loadedState)

        sut.applySentMessage(.make(id: 50, conversationId: 2, createdAt: .stub(500)))

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

        sut.applySentMessage(.make(id: 50, conversationId: 3, createdAt: .stub(500)))
        await eventQueue.send(.edited(Message.make(id: 15, conversationId: 1, text: "Правка").withUpdatedAt(.stub(600))))

        XCTAssertEqual(sut.conversations.map(\.id), [3, 1, 2])
        XCTAssertEqual(sut.conversations.map(\.lastMessage?.text)[1], "Правка")
    }

    /// Кейс: ответ `/messages/send` по переписке, которой нет в списке.
    /// Ожидание: переписка загружена через `getBatch` и вставлена с отправленным сообщением.
    func test_applySentMessage_unknownConversation_loadsBatch() async {
        await start(cache: [.make(id: 1, position: .stub(-10))], state: loadedState)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 5, position: .stub(-900))], notFoundIds: []))]

        sut.applySentMessage(.make(id: 50, conversationId: 5, createdAt: .stub(500)))

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

        sut.applySentMessage(.make(id: 50, conversationId: 2, createdAt: .stub(500)))
        gate.open()
        await yieldUntil { [unowned self] in !sut.isSyncing }

        XCTAssertEqual(sut.conversations.map(\.id), [2, 1])
        XCTAssertEqual(sut.conversations.first?.lastMessage?.messageId, 50)
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
        await start(cache: [.make(id: 1)], state: ConversationListState(isLoaded: true, hasMorePages: false, positionWatermark: .stub, positionWatermarkCeiling: nil, infoWatermark: nil))
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
        await start(cache: [.make(id: 1)], state: noInfoState)
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
        await start(cache: cache, state: noInfoState)
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
        await start(cache: cache, state: noInfoState)
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

    // MARK: - Helpers

    /// Создаёт сервис над моками теста.
    private func makeSUT() -> ConversationListService {
        ConversationListService(conversationService: conversationService, storage: storage, eventQueue: eventQueue, userCache: userCache)
    }

    /// Запускает сервис над заданным кэшем и дожидается чтения кэша.
    /// - Parameters:
    ///   - cache: переписки в БД.
    ///   - state: состояние синхронизации в БД.
    private func start(cache: [Conversation] = [], state: ConversationListState = ConversationListState()) async {
        storage.stubbedList = .success((cache, state))
        sut.start()
        // Обработчик любого события, кроме `connected`, ждёт чтения кэша; `edited` без превью ничего не меняет.
        await eventQueue.send(.messageEdited(.stub, nil))
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
    private func page(_ conversations: [Conversation], hasNext: Bool = false) -> ConversationsPage {
        ConversationsPage(conversations: conversations, hasNext: hasNext)
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
