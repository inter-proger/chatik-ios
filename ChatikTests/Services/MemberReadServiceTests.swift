//
//  MemberReadServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MemberReadServiceTests: XCTestCase {
    private var conversationService: ConversationServiceMock!
    private var storage: MemberReadStorageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var sut: MemberReadService!

    override func setUp() async throws {
        try await super.setUp()
        conversationService = ConversationServiceMock()
        storage = MemberReadStorageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        let session = SessionService(
            userDefaultsService: UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)),
            localStorageCleaner: LocalStorageCleanerMock()
        )
        await session.restore()
        sut = MemberReadService(
            conversationService: conversationService,
            storage: storage,
            eventQueue: eventQueue,
            sessionService: session
        )
    }

    // MARK: - Наблюдение

    /// Кейс: у переписки есть сохранённая мета; экран открыт, запрос ещё не ответил.
    /// Ожидание: сохранённые указатели и порог опубликованы сразу, затем ушёл запрос.
    func test_beginObserving_publishesStoredThenRefreshes() async {
        storage.stored = [7: [2: 10, 3: 12]]
        let gate = Gate()
        conversationService.onFetchMembersReadMeta = { await gate.wait() }

        sut.beginObserving(conversationId: 7)

        await yieldUntil { gate.isWaiting }
        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 10, 3: 12])
        XCTAssertEqual(sut.readUpTo(conversationId: 7), 12)
        XCTAssertEqual(conversationService.membersReadMetaRequests, [7])
        gate.open()
    }

    /// Кейс: меты нет ни в БД, ни в ответе (запрос не удался).
    /// Ожидание: указателей и порога нет — две галочки не показываются без данных.
    func test_beginObserving_withoutMeta_hasNoPointers() async {
        sut.beginObserving(conversationId: 7)

        await yieldUntil { [unowned self] in conversationService.membersReadMetaRequests == [7] }
        await yieldTimes()
        XCTAssertNil(sut.pointers(conversationId: 7))
        XCTAssertNil(sut.readUpTo(conversationId: 7))
    }

    /// Кейс: меты нет, запрос не удался; затем повторный запрос успешен.
    /// Ожидание: после сбоя отмечена ошибка запроса, после успешного повтора отметка снята.
    func test_refresh_failure_marksFailedUntilNextRefresh() async {
        conversationService.stubbedMembersReadMeta = [.failure(NetworkError.missingResponse), .success([MemberReadMeta(userId: 2, lastReadMessageId: 3)])]
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.isRefreshFailed(conversationId: 7) }

        sut.refresh(conversationId: 7)

        XCTAssertFalse(sut.isRefreshFailed(conversationId: 7))
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) == [2: 3] }
        XCTAssertFalse(sut.isRefreshFailed(conversationId: 7))
    }

    /// Кейс: в БД указатели участников 2 и 3; ответ — участники 2 (меньший указатель) и 4.
    /// Ожидание: 3 удалён, у 2 — максимум, 4 добавлен; в БД ушёл ответ с составом участников.
    func test_refresh_response_mergesByMaximumAndRemovesMissingMembers() async {
        storage.stored = [7: [2: 10, 3: 12]]
        conversationService.stubbedMembersReadMeta = [.success([MemberReadMeta(userId: 2, lastReadMessageId: 8), MemberReadMeta(userId: 4, lastReadMessageId: 5)])]

        sut.beginObserving(conversationId: 7)

        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) == [2: 10, 4: 5] }
        await yieldUntil { [unowned self] in storage.stored[7] == [2: 10, 4: 5] }
        XCTAssertEqual(storage.applied.last?[7]?.members, [2, 4])
    }

    /// Кейс: запрос завершился ошибкой.
    /// Ожидание: показанной остаётся сохранённая мета.
    func test_refresh_failure_keepsStoredMeta() async {
        storage.stored = [7: [2: 10]]

        sut.beginObserving(conversationId: 7)

        await yieldUntil { [unowned self] in conversationService.membersReadMetaRequests == [7] }
        await yieldTimes()
        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 10])
    }

    /// Кейс: ответ сервера применён раньше, чем дочиталась БД; в БД есть ушедший участник 3.
    /// Ожидание: из БД берётся только максимум для известных участников — ушедший не возвращается.
    func test_loadStored_afterResponse_doesNotRestoreRemovedMembers() async {
        storage.stored = [7: [2: 15, 3: 12]]
        let storageGate = Gate()
        storage.fetchPointersGate = storageGate
        conversationService.stubbedMembersReadMeta = [.success([MemberReadMeta(userId: 2, lastReadMessageId: 10)])]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { storageGate.isWaiting }
        storage.fetchPointersGate = nil

        await eventQueue.send(.connected)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) == [2: 10] }
        storageGate.open()

        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) == [2: 15] }
    }

    /// Кейс: запрос идёт; пока он не ответил, `refresh` вызывается ещё дважды.
    /// Ожидание: запрос один — запросы склеиваются.
    func test_refresh_whileInFlight_isCoalesced() async {
        let gate = Gate()
        conversationService.onFetchMembersReadMeta = { await gate.wait() }
        sut.beginObserving(conversationId: 7)
        await yieldUntil { gate.isWaiting }

        sut.refresh(conversationId: 7)
        sut.refresh(conversationId: 7)

        XCTAssertEqual(conversationService.membersReadMetaRequests, [7])
        gate.open()
    }

    /// Кейс: переписка открыта в двух сценах, одна закрылась.
    /// Ожидание: мета остаётся в памяти до закрытия последней.
    func test_endObserving_keepsMetaUntilLastObserver() async {
        storage.stored = [7: [2: 10]]
        sut.beginObserving(conversationId: 7)
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) != nil }

        sut.endObserving(conversationId: 7)
        let afterFirst = sut.pointers(conversationId: 7)
        sut.endObserving(conversationId: 7)

        XCTAssertEqual(afterFirst, [2: 10])
        XCTAssertNil(sut.pointers(conversationId: 7))
    }

    // MARK: - События

    /// Кейс: `memberRead` для наблюдаемой переписки — сначала больше известного указателя, затем меньше.
    /// Ожидание: в памяти и в БД — максимум, неизвестный участник добавлен.
    func test_memberRead_observed_mergesByMaximum() async {
        storage.stored = [7: [2: 10]]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) != nil }

        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 15))
        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 12))
        await eventQueue.send(.memberRead(conversationId: 7, userId: 3, lastReadMessageId: 4))

        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 15, 3: 4])
        await yieldUntil { [unowned self] in storage.stored[7] == [2: 15, 3: 4] }
    }

    /// Кейс: в наблюдаемой переписке приходят `memberRead` и сообщение участника, не сдвигающие его указатель.
    /// Ожидание: в БД ничего не пишется — указатель в памяти уже записан.
    func test_memberRead_observedWithoutGrowth_doesNotWrite() async {
        storage.stored = [7: [2: 10]]
        conversationService.stubbedMembersReadMeta = [.success([MemberReadMeta(userId: 2, lastReadMessageId: 10)])]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in storage.applied.count == 1 }
        await yieldTimes()

        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 10))
        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 8))
        await eventQueue.send(.received(.make(id: 9, conversationId: 7, senderId: 2)))

        await yieldTimes()
        XCTAssertEqual(storage.applied.count, 1)
        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 10])
    }

    /// Кейс: `memberRead` для ненаблюдаемой переписки с сохранённой метой и для переписки без меты.
    /// Ожидание: первая обновлена в БД (в памяти указателей нет), второй мета не создана и запись не ставилась.
    func test_memberRead_unobserved_updatesOnlyStoredConversations() async {
        storage.stored = [8: [2: 1]]
        sut.start()
        await yieldTimes()

        await eventQueue.send(.memberRead(conversationId: 8, userId: 2, lastReadMessageId: 5))
        await eventQueue.send(.memberRead(conversationId: 9, userId: 2, lastReadMessageId: 5))

        await yieldUntil { [unowned self] in storage.stored[8] == [2: 5] }
        XCTAssertNil(sut.pointers(conversationId: 8))
        XCTAssertNil(storage.stored[9])
        XCTAssertNil(storage.applied.flatMap(\.keys).first { $0 == 9 })
    }

    /// Кейс: `memberRead` для ненаблюдаемой переписки, пока список переписок с метой ещё читается из БД.
    /// Ожидание: запись ставится с условием «только если мета есть» — решает хранилище.
    func test_memberRead_beforeStoredIdsLoaded_writesIfStored() async {
        let gate = Gate()
        storage.fetchConversationIdsGate = gate
        sut.start()
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.memberRead(conversationId: 9, userId: 2, lastReadMessageId: 5))

        await yieldUntil { [unowned self] in !storage.applied.isEmpty }
        XCTAssertEqual(storage.applied.first?[9], MemberReadWrite(pointers: [2: 5], createsMissing: false))
        XCTAssertNil(storage.stored[9])
        gate.open()
    }

    /// Кейс: новое сообщение собеседника и своё новое сообщение в наблюдаемой переписке.
    /// Ожидание: указатель собеседника сдвинут на его сообщение; своё сообщение указатели не двигает.
    func test_messageReceived_movesSenderPointerExceptOwn() async {
        storage.stored = [1: [2: 10]]
        sut.start()
        sut.beginObserving(conversationId: 1)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 1) != nil }

        await eventQueue.send(.received(.make(id: 20, conversationId: 1, senderId: 2)))
        await eventQueue.send(.received(.make(id: 21, conversationId: 1, senderId: 1)))

        XCTAssertEqual(sut.pointers(conversationId: 1), [2: 20])
    }

    /// Кейс: чтение переписок с метой из БД не удалось; затем соединение переустановлено, и чтение успешно.
    /// Ожидание: чтение повторено; после него событие для переписки без меты в БД не пишется.
    func test_storedIdsFailure_isRetriedOnConnected() async {
        storage.stubbedFetchConversationIdsError = NetworkError.missingResponse
        sut.start()
        await yieldUntil { [unowned self] in storage.fetchConversationIdsCount == 1 }
        await yieldTimes()
        storage.stubbedFetchConversationIdsError = nil

        await eventQueue.send(.connected)
        await yieldUntil { [unowned self] in storage.fetchConversationIdsCount == 2 }
        await yieldTimes()
        await eventQueue.send(.memberRead(conversationId: 9, userId: 2, lastReadMessageId: 5))

        await yieldTimes()
        XCTAssertTrue(storage.applied.isEmpty)
    }

    /// Кейс: переписки с метой уже прочитаны из БД; соединение переустановлено.
    /// Ожидание: повторного чтения нет.
    func test_storedIdsLoaded_notReloadedOnConnected() async {
        sut.start()
        await yieldUntil { [unowned self] in storage.fetchConversationIdsCount == 1 }
        await yieldTimes()

        await eventQueue.send(.connected)

        await yieldTimes()
        XCTAssertEqual(storage.fetchConversationIdsCount, 1)
    }

    /// Кейс: открыта одна переписка из двух с сохранённой метой; соединение переустановлено.
    /// Ожидание: заново запрашивается только наблюдаемая переписка.
    func test_connected_refreshesOnlyObserved() async {
        storage.stored = [7: [2: 1], 8: [2: 1]]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in conversationService.membersReadMetaRequests == [7] }
        await yieldTimes()

        await eventQueue.send(.connected)

        await yieldUntil { [unowned self] in conversationService.membersReadMetaRequests == [7, 7] }
    }

    // MARK: - Порог

    /// Кейс: порог 15; приходит меньший указатель другого участника, затем ответ без участника с порогом 15.
    /// Ожидание: порог не меняется — он только растёт, а прочтение не отменяется.
    func test_readUpTo_neverDecreases() async {
        storage.stored = [7: [2: 15, 3: 5]]
        let gate = Gate()
        conversationService.onFetchMembersReadMeta = { await gate.wait() }
        conversationService.stubbedMembersReadMeta = [.success([MemberReadMeta(userId: 3, lastReadMessageId: 6)])]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.memberRead(conversationId: 7, userId: 3, lastReadMessageId: 9))
        let afterEvent = sut.readUpTo(conversationId: 7)
        gate.open()

        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) == [3: 9] }
        XCTAssertEqual(afterEvent, 15)
        XCTAssertEqual(sut.readUpTo(conversationId: 7), 15)
    }

    /// Кейс: указатель вырос выше порога.
    /// Ожидание: порог поднялся до нового максимума.
    func test_readUpTo_growsWithMaximum() async {
        storage.stored = [7: [2: 10]]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.readUpTo(conversationId: 7) == 10 }

        await eventQueue.send(.memberRead(conversationId: 7, userId: 3, lastReadMessageId: 14))

        XCTAssertEqual(sut.readUpTo(conversationId: 7), 14)
    }

    // MARK: - Запись

    /// Кейс: запись в БД идёт; за это время приходят два события.
    /// Ожидание: события ушли одной следующей пачкой со слитыми указателями.
    func test_writes_duringInFlightWrite_areCoalesced() async {
        storage.stored = [8: [2: 1]]
        sut.start()
        await yieldTimes()
        let gate = Gate()
        storage.nextApplyGate = gate
        await eventQueue.send(.memberRead(conversationId: 8, userId: 2, lastReadMessageId: 2))
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.memberRead(conversationId: 8, userId: 2, lastReadMessageId: 3))
        await eventQueue.send(.memberRead(conversationId: 8, userId: 3, lastReadMessageId: 1))
        gate.open()

        await yieldUntil { [unowned self] in storage.applied.count == 2 }
        await yieldTimes()
        XCTAssertEqual(storage.applied.count, 2)
        XCTAssertEqual(storage.applied.last?[8]?.pointers, [2: 3, 3: 1])
    }

    // MARK: - Выход из аккаунта

    /// Кейс: идёт запись, ещё одно изменение ждёт; начинается выход из аккаунта.
    /// Ожидание: выход дожидается идущей записи, ждущее изменение отброшено, память сброшена; события во время
    /// выхода не применяются.
    func test_willLogout_waitsForWriteAndDropsPending() async {
        storage.stored = [7: [2: 1]]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) != nil }
        await yieldTimes()
        let gate = Gate()
        storage.nextApplyGate = gate
        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 5))
        await yieldUntil { gate.isWaiting }
        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 6))
        let appliedBefore = storage.applied.count

        let logout = Task { await sut.authServiceWillLogout() }
        await yieldTimes()
        await eventQueue.send(.memberRead(conversationId: 7, userId: 2, lastReadMessageId: 7))
        gate.open()
        await logout.value

        XCTAssertEqual(storage.applied.count, appliedBefore)
        XCTAssertNil(sut.pointers(conversationId: 7))
        XCTAssertEqual(storage.stored[7], [2: 5])
    }
}
