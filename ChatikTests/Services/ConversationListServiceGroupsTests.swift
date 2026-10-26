//
//  ConversationListServiceGroupsTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

/// Группы в списке переписок: создание, добавление текущего пользователя, метки удаления, выход, проверка членства
/// и каскад (`docs/group-chats.md`, решения 4–6).
@MainActor
final class ConversationListServiceGroupsTests: XCTestCase {
    private var conversationService: ConversationServiceMock!
    private var storage: ConversationStorageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var removalObserver: RemovalObserverSpy!
    private var sut: ConversationListService!

    /// Загруженный список без продолжения: курсор изменений — 10.
    private let loadedState = ConversationListState(
        isLoaded: true,
        hasMorePages: false,
        positionWatermark: .stub,
        positionWatermarkCeiling: nil,
        syncedChangeVersion: 10
    )

    override func setUp() async throws {
        try await super.setUp()
        conversationService = ConversationServiceMock()
        storage = ConversationStorageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        removalObserver = RemovalObserverSpy()
        sut = ConversationListService(
            conversationService: conversationService,
            storage: storage,
            eventQueue: eventQueue,
            userCache: UserCacheServiceMock()
        )
        sut.addRemovalObserver(removalObserver)
    }

    // MARK: - Создание

    /// Кейс: событие `groups` / `created` с версией на 1 больше курсора.
    /// Ожидание: группа вставлена, курсор продвинут до версии события.
    func test_created_insertsAndAdvancesCursor() async {
        await start(cache: [.make(id: 1, position: .stub(-10))])

        await eventQueue.send(.group(.created(.make(id: 12, position: .stub(10), readState: .make(version: 11)), info(12))))

        XCTAssertEqual(sut.conversations.map(\.id), [12, 1])
        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 11 }
    }

    // MARK: - Добавление в группу

    /// Кейс: текущего пользователя добавили в группу (`membersAdded` с версией 11).
    /// Ожидание: ссылка записана в БД до `getBatch`; группа вставлена наверх; ссылка снята, курсор продвинут.
    func test_membersAdded_storesPendingBeforeRequestThenInserts() async {
        await start(cache: [.make(id: 1, position: .stub(-10))])
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, position: .stub(50), readState: .make(version: 11))], notFoundIds: []))]
        var pendingAtRequest: [Int: Int]?
        conversationService.onRequest = { [unowned self] in pendingAtRequest = storage.lastState?.pendingConversations }

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 11)))

        XCTAssertEqual(pendingAtRequest, [12: 11])
        XCTAssertEqual(conversationService.batchRequests, [[12]])
        XCTAssertEqual(sut.conversations.map(\.id), [12, 1])
        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations.isEmpty == true }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 11)
    }

    /// Кейс: `getBatch` добавленной группы не удался; затем пришёл `connected`, и после синхронизации повтор успешен.
    /// Ожидание: после сбоя ссылка остаётся, курсор не двигается; повтор после основной фазы вставляет группу.
    func test_membersAdded_failureKeepsPendingAndRetriesAfterSync() async {
        await start(cache: [.make(id: 1, position: .stub(-10))])
        conversationService.stubbedBatches = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 11)))
        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations == [12: 11] }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 10)

        conversationService.stubbedPages = [.success(page([]))]
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, position: .stub(50), readState: .make(version: 11))], notFoundIds: []))]
        await connect()

        await yieldUntil { [unowned self] in sut.conversations.map(\.id) == [12, 1] }
        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations.isEmpty == true }
    }

    /// Кейс: добавленную группу успели удалить — `getBatch` вернул её в `notFoundIds`.
    /// Ожидание: ничего не вставлено, ссылка снята, версия отмечена для курсора.
    func test_membersAdded_notFound_dropsPendingAndAdvancesCursor() async {
        await start(cache: [.make(id: 1)])
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [], notFoundIds: [12]))]

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 11)))

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 11 }
        XCTAssertEqual(storage.lastState?.pendingConversations, [:])
    }

    /// Кейс: `membersAdded` с версией не новее метки удаления этой группы (событие опоздало).
    /// Ожидание: группа не запрашивается и в ожидание не ставится; версия отмечена для курсора.
    func test_membersAdded_staleByMark_onlyNotesCursor() async {
        var state = loadedState
        state.removedVersions = [12: 12]
        await start(cache: [.make(id: 1)], state: state)

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 11)))

        XCTAssertTrue(conversationService.batchRequests.isEmpty)
        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 11 }
        XCTAssertEqual(storage.lastState?.pendingConversations, [:])
    }

    /// Кейс: у списка есть продолжение, а время вступления в группу старше последней загруженной переписки.
    /// Ожидание: группа не вставлена (иначе разорвался бы префикс), ссылка снята — группу принесёт пагинация.
    func test_membersAdded_olderThanTailWithMorePages_isNotInserted() async {
        var state = loadedState
        state.hasMorePages = true
        await start(cache: [.make(id: 1, position: .stub(-10))], state: state)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, position: .stub(-500), readState: .make(version: 11))], notFoundIds: []))]

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 11)))

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations.isEmpty == true }
    }

    // MARK: - Метки удаления

    /// Кейс: текущего пользователя удалили из загруженной группы «Команда» (`membersRemoved` с меткой 11 и счётчиком 3).
    /// Ожидание: группа удалена из списка и БД, метка сохранена, общий счётчик и курсор применены; каскад вызван один
    /// раз с названием и причиной `.removed`.
    func test_membersRemoved_loadedGroup_removesAndRunsCascade() async {
        await start(cache: [.make(id: 1), .make(id: 12).with(name: "Команда", updatedInfoAt: .stub)])

        await eventQueue.send(.group(.membersRemoved(conversationId: 12, removedUserIds: [1], groupInfo: nil, removal: removal(12, version: 11, total: 3))))

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertEqual(sut.totalUnreadCount, 3)
        await yieldUntil { [unowned self] in removalObserver.infos.count == 1 }
        XCTAssertEqual(removalObserver.infos, [RemovedConversationInfo(conversationId: 12, name: "Команда", type: .group, reason: .removed, changeVersion: 11)])
        XCTAssertEqual(storage.deletions.map(\.conversationId), [12])
        XCTAssertEqual(storage.lastState?.removedVersions, [12: 11])
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 11)
    }

    /// Кейс: метка удаления старше локальной версии группы (пользователя уже добавили обратно).
    /// Ожидание: метка устарела — группа остаётся, каскада нет.
    func test_removal_olderThanLocalVersion_isIgnored() async {
        await start(cache: [.make(id: 12, readState: .make(version: 20))])

        await eventQueue.send(.group(.memberLeft(conversationId: 12, leftUserId: 1, groupInfo: nil, removal: removal(12, version: 11))))

        XCTAssertEqual(sut.conversations.map(\.id), [12])
        XCTAssertTrue(removalObserver.infos.isEmpty)
    }

    /// Кейс: удаление из группы, которой нет в загруженном списке.
    /// Ожидание: метка сохранена, каскад вызван без названия — у других сервисов могут быть данные группы.
    func test_removal_unloadedGroup_storesMarkAndRunsCascade() async {
        await start(cache: [.make(id: 1)])

        await eventQueue.send(.group(.membersRemoved(conversationId: 12, removedUserIds: [1], groupInfo: nil, removal: removal(12, version: 11))))

        await yieldUntil { [unowned self] in removalObserver.infos.count == 1 }
        XCTAssertEqual(removalObserver.infos.first?.name, nil)
        XCTAssertEqual(storage.lastState?.removedVersions, [12: 11])
    }

    /// Кейс: после метки 11 приходят полные версии группы: из `getBatch` по событию `received` с версией 11
    /// (собрана до удаления) и затем с версией 12 (пользователя добавили снова).
    /// Ожидание: версия 11 отброшена; версия 12 принята, метка снята.
    func test_filter_dropsVersionNotNewerThanMarkAndAcceptsNewer() async {
        var state = loadedState
        state.removedVersions = [12: 11]
        await start(cache: [.make(id: 1, position: .stub(-10))], state: state)
        conversationService.stubbedBatches = [
            .success(ConversationsBatch(conversations: [.make(id: 12, readState: .make(version: 11))], notFoundIds: [])),
            .success(ConversationsBatch(conversations: [.make(id: 12, readState: .make(version: 12))], notFoundIds: [])),
        ]

        await eventQueue.send(.received(.make(id: 30, conversationId: 12, createdAt: .stub(100))))
        XCTAssertEqual(sut.conversations.map(\.id), [1])

        await eventQueue.send(.received(.make(id: 31, conversationId: 12, createdAt: .stub(200))))
        XCTAssertEqual(sut.conversations.map(\.id), [12, 1])
        XCTAssertFalse(sut.isRemoved(conversationId: 12, changeVersion: 12))
    }

    /// Кейс: метка удаления снимает ожидающую группу.
    /// Ожидание: после метки `pendingConversations` пуст.
    func test_removal_clearsPendingConversation() async {
        var state = loadedState
        state.pendingConversations = [12: 11]
        await start(cache: [.make(id: 1)], state: state)

        await eventQueue.send(.group(.membersRemoved(conversationId: 12, removedUserIds: [1], groupInfo: nil, removal: removal(12, version: 12))))

        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations.isEmpty == true }
    }

    // MARK: - Выход

    /// Кейс: свой выход — ответ `leave` пришёл раньше события `memberLeft` той же версии.
    /// Ожидание: группа удалена один раз с причиной `.left`; версия события отмечена для курсора.
    func test_leave_responseThenEvent_removesOnceAsLeft() async {
        await start(cache: [.make(id: 12)])
        sut.beginLeaving(conversationId: 12)

        sut.applyLeave(removal(12, version: 11))
        sut.endLeaving(conversationId: 12)
        await eventQueue.send(.group(.memberLeft(conversationId: 12, leftUserId: 1, groupInfo: nil, removal: removal(12, version: 11))))

        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 11 }
        XCTAssertEqual(removalObserver.infos.map(\.reason), [.left])
        XCTAssertTrue(sut.conversations.isEmpty)
    }

    /// Кейс: событие `memberLeft` пришло раньше ответа `leave`, пока выход в полёте.
    /// Ожидание: удаление одно, причина `.left`, ответ ничего не повторяет.
    func test_leave_eventThenResponse_removesOnceAsLeft() async {
        await start(cache: [.make(id: 12)])
        sut.beginLeaving(conversationId: 12)

        await eventQueue.send(.group(.memberLeft(conversationId: 12, leftUserId: 1, groupInfo: nil, removal: removal(12, version: 11))))
        sut.applyLeave(removal(12, version: 11))
        sut.endLeaving(conversationId: 12)

        await yieldUntil { [unowned self] in removalObserver.infos.count == 1 }
        XCTAssertEqual(removalObserver.infos.map(\.reason), [.left])
        XCTAssertEqual(storage.deletions.count, 1)
    }

    /// Кейс: ответ `leave` применён (REST, версия 11), событие не пришло.
    /// Ожидание: курсор не двигается — то же изменение придёт событием.
    func test_leave_responseDoesNotMoveCursor() async {
        await start(cache: [.make(id: 12)])

        sut.applyLeave(removal(12, version: 11))

        await yieldUntil { [unowned self] in storage.deletions.count == 1 }
        XCTAssertEqual(storage.lastState?.syncedChangeVersion, 10)
    }

    // MARK: - Синхронизация

    /// Кейс: сверка `changedAfter` вернула переписку на версии 11 и метку удаления группы на версии 13, продолжения нет.
    /// Ожидание: группа удалена с причиной `.lostAccess`; курсор — максимум по обеим частям, 13.
    func test_changeSync_appliesRemovedConversationsAndCursorFromBoth() async {
        await start(cache: [.make(id: 1), .make(id: 12)])
        conversationService.stubbedPages = [.success(page([]))]
        conversationService.stubbedChangePages = [.success(ConversationsPage(
            conversations: [.make(id: 1, readState: .make(version: 11))],
            removedConversations: [RemovedConversation(conversationId: 12, changeVersion: 13)],
            hasNext: false,
            totalUnreadCount: 0,
            changeVersion: 12
        ))]

        await connect()

        await yieldUntil { [unowned self] in storage.lastState?.syncedChangeVersion == 13 }
        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertEqual(removalObserver.infos.map(\.reason), [.lostAccess])
    }

    /// Кейс: полная загрузка; в памяти метки 5 (не новее версии страницы 10) и 20 (ответ `leave`, пришедший, пока
    /// страница была в полёте); страница содержит обе группы с версиями 4 и 9.
    /// Ожидание: метка 5 снята (страница её учитывает), метка 20 осталась и отфильтровала группу из страницы.
    func test_replaceList_keepsNewerMarksAndFiltersPage() async {
        var state = ConversationListState()
        state.removedVersions = [5: 5, 20: 20]
        await start(cache: [], state: state)
        conversationService.stubbedPages = [.success(page([.make(id: 5, readState: .make(version: 4)), .make(id: 20, readState: .make(version: 9))]))]

        await connect()

        XCTAssertEqual(sut.conversations.map(\.id), [5])
        XCTAssertTrue(sut.isRemoved(conversationId: 20, changeVersion: 9))
        XCTAssertFalse(sut.isRemoved(conversationId: 5, changeVersion: 4))
    }

    // MARK: - Проверка членства

    /// Кейс: проверка членства вызвана дважды подряд; `getBatch` вернул группу в `notFoundIds`.
    /// Ожидание: один запрос; группа удалена с причиной `.lostAccess` и меткой на своей локальной версии.
    func test_verifyMembership_notFound_removesOnce() async {
        await start(cache: [.make(id: 12, readState: .make(version: 7))])
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [], notFoundIds: [12]))]

        sut.verifyMembership(conversationId: 12)
        sut.verifyMembership(conversationId: 12)

        await yieldUntil { [unowned self] in removalObserver.infos.count == 1 }
        XCTAssertEqual(conversationService.batchRequests, [[12]])
        XCTAssertTrue(sut.isRemoved(conversationId: 12, changeVersion: 7))
        XCTAssertEqual(removalObserver.infos.map(\.reason), [.lostAccess])
    }

    /// Кейс: `markRead` по группе ответил `5002`.
    /// Ожидание: запущена проверка членства — `getBatch` по группе.
    func test_markRead_conversationNotFound_verifiesMembership() async {
        await start(cache: [.make(id: 12, readState: .make(unread: 1, lastRead: 1, version: 10))])
        conversationService.stubbedReadInfos = [.failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))]
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, readState: .make(version: 10))], notFoundIds: []))]

        sut.markRead(conversationId: 12, messageId: 5)

        await yieldUntil { [unowned self] in conversationService.batchRequests == [[12]] }
    }

    // MARK: - Ревью реализации

    /// Кейс: выход с другого устройства — событие `memberLeft` с меткой, запроса выхода здесь нет.
    /// Ожидание: причина `.leftOnOtherDevice` — экран покажет «Вы больше не участник группы».
    func test_memberLeft_withoutLeaveRequest_isLeftOnOtherDevice() async {
        await start(cache: [.make(id: 12)])

        await eventQueue.send(.group(.memberLeft(conversationId: 12, leftUserId: 1, groupInfo: nil, removal: removal(12, version: 11))))

        await yieldUntil { [unowned self] in removalObserver.infos.count == 1 }
        XCTAssertEqual(removalObserver.infos.map(\.reason), [.leftOnOtherDevice])
    }

    /// Кейс: во время основной фазы синхронизации группа применена локально (`apply`), затем пришёл ответ `leave`;
    /// страница полной загрузки собрана на версии не меньше метки и группы не содержит.
    /// Ожидание: метка снята страницей, но отложенная версия группы не возвращает её в список.
    func test_replaceList_pendingLocalUpdateOfRemovedGroup_isDropped() async {
        await start(cache: [], state: ConversationListState())
        let gate = Gate()
        conversationService.onRequest = { await gate.wait() }
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.make(id: 1)], hasNext: false, totalUnreadCount: 0, changeVersion: 20))]
        let connecting = Task { [eventQueue] in await eventQueue!.send(.connected) }
        await yieldUntil { gate.isWaiting }

        sut.apply(.make(id: 12, readState: .make(version: 5)))
        sut.applyLeave(removal(12, version: 11))
        gate.open()
        await connecting.value
        await yieldUntil { [unowned self] in !sut.isSyncing }

        XCTAssertEqual(sut.conversations.map(\.id), [1])
    }

    /// Кейс: проверка членства нашла переписку, которой нет в загруженном списке (открыта из уведомления).
    /// Ожидание: переписка не вставляется за хвост списка — только слияние с уже загруженной.
    func test_verifyMembership_found_doesNotInsertUnknown() async {
        var state = loadedState
        state.hasMorePages = true
        await start(cache: [.make(id: 1)], state: state)
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 40, position: .stub(-9000))], notFoundIds: []))]

        sut.verifyMembership(conversationId: 40)

        await yieldUntil { [unowned self] in conversationService.batchRequests == [[40]] }
        await yieldTimes()
        XCTAssertEqual(sut.conversations.map(\.id), [1])
    }

    /// Кейс: полная загрузка; одна из трёх переписок страницы отброшена меткой удаления.
    /// Ожидание: сдвиг следующей страницы — 2 (без отброшенной): на сервере её уже нет, пропуска не будет.
    func test_replaceList_offsetExcludesFilteredConversations() async {
        var state = ConversationListState()
        state.removedVersions = [3: 30]
        await start(cache: [], state: state)
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: [.make(id: 1), .make(id: 2), .make(id: 3, readState: .make(version: 9))], hasNext: true, totalUnreadCount: 0, changeVersion: 10)),
            .success(page([])),
        ]
        await connect()

        sut.loadNextPageIfNeeded(currentConversationId: 2)

        await yieldUntil { [unowned self] in conversationService.requests.count == 2 }
        XCTAssertEqual(conversationService.requests.last?.filter, .none(offset: 2))
    }

    /// Кейс: удалили из группы (метка 11), и сразу вернули (`membersAdded` с версией 12) — каскад метки ещё в очереди.
    /// Ожидание: каскад метки 11 не выполняется: данные возвращённой группы не стираются.
    func test_cascade_skippedAfterRejoin() async {
        await start(cache: [.make(id: 12)])
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, readState: .make(version: 12))], notFoundIds: []))]

        await eventQueue.send(.group(.membersRemoved(conversationId: 12, removedUserIds: [1], groupInfo: nil, removal: removal(12, version: 11))))
        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12), changeVersion: 12)))
        await yieldTimes()

        XCTAssertTrue(removalObserver.infos.isEmpty)
        XCTAssertEqual(sut.conversations.map(\.id), [12])
    }

    /// Кейс: ссылка на добавленную группу сохранена до перезапуска, список без продолжения; приходит `connected`.
    /// Ожидание: после основной фазы группа загружена и вставлена; ссылка снята.
    func test_pending_survivesRestartAndInsertsWithoutMorePages() async {
        var state = loadedState
        state.pendingConversations = [12: 11]
        await start(cache: [.make(id: 1, position: .stub(-10))], state: state)
        conversationService.stubbedPages = [.success(page([]))]
        conversationService.stubbedBatches = [.success(ConversationsBatch(conversations: [.make(id: 12, position: .stub(-9000), readState: .make(version: 11))], notFoundIds: []))]

        await connect()

        await yieldUntil { [unowned self] in sut.conversations.map(\.id) == [1, 12] }
        await yieldUntil { [unowned self] in storage.lastState?.pendingConversations.isEmpty == true }
    }

    // MARK: - Helpers

    /// Запускает сервис над кэшем и дожидается его чтения.
    /// - Parameters:
    ///   - cache: переписки в БД.
    ///   - state: состояние синхронизации; по умолчанию — загруженный список с курсором 10.
    private func start(cache: [Conversation], state: ConversationListState? = nil) async {
        storage.stubbedList = .success((cache, state ?? loadedState))
        sut.start()
        await eventQueue.send(.messageEdited(.stub, nil, changeVersion: nil))
    }

    /// Доставляет `connected` и ждёт окончания основной фазы синхронизации.
    private func connect(file: StaticString = #filePath, line: UInt = #line) async {
        await eventQueue.send(.connected)
        await yieldUntil(file: file, line: line) { [unowned self] in !sut.isSyncing && eventQueue.activeLeaseCount == 0 }
    }

    /// Страница списка без продолжения на версии 10.
    /// - Parameter conversations: переписки.
    private func page(_ conversations: [Conversation]) -> ConversationsPage {
        ConversationsPage(conversations: conversations, hasNext: false, totalUnreadCount: 0, changeVersion: 10)
    }

    /// Состав группы из одного владельца — текущего пользователя.
    /// - Parameter conversationId: группа.
    private func info(_ conversationId: Int) -> GroupInfo {
        GroupInfo(conversationId: conversationId, version: 1, members: [GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0)])
    }

    /// Метка удаления со счётчиком.
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - version: версия метки.
    ///   - total: общий счётчик непрочитанных.
    private func removal(_ conversationId: Int, version: Int, total: Int = 0) -> ConversationRemoval {
        ConversationRemoval(removedConversation: RemovedConversation(conversationId: conversationId, changeVersion: version), totalUnreadCount: total)
    }
}

/// Наблюдатель каскада удаления: запоминает удалённые переписки по порядку.
@MainActor
final class RemovalObserverSpy: ConversationRemovalObserver {
    private(set) var infos: [RemovedConversationInfo] = []

    func conversationWasRemoved(_ info: RemovedConversationInfo) async {
        infos.append(info)
    }
}
