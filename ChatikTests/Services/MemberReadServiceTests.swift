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
    /// Проверка членства — мок списка переписок.
    private var membership = ConversationListServiceMock()

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
            sessionService: session,
            membership: membership,
            groupInfo: nil
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

    // MARK: - Удаление переписки

    /// Кейс: у группы 7 сохранена мета и она наблюдается; пользователя удалили из группы.
    /// Ожидание: мета удалена из памяти и БД.
    func test_conversationWasRemoved_deletesMeta() async {
        storage.stored = [7: [2: 10]]
        sut.start()
        sut.beginObserving(conversationId: 7)
        await yieldUntil { [unowned self] in sut.pointers(conversationId: 7) != nil }

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 7, name: nil, type: .group, reason: .removed, changeVersion: 1))

        XCTAssertNil(sut.pointers(conversationId: 7))
        XCTAssertEqual(storage.deletedConversationIds, [7])
        XCTAssertNil(storage.stored[7])
    }


    // MARK: - Группы

    /// Кейс: группа 7: участник 2 вступил до сообщения 0 и прочитал до 10, участник 3 вступил после 20 — его указатель
    /// сервер поставил на последнее сообщение 25.
    /// Ожидание: прочитаны сообщения 1–10 и 21–25; сообщения 11–20 — нет: новичок их не читал.
    func test_group_coverageRespectsJoinTime() async {
        let groupInfo = GroupInfoServiceMock()
        groupInfo.infos[7] = GroupInfo(conversationId: 7, version: 2, members: [
            GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0),
            GroupMember(userId: 2, role: .member, joinedAfterMessageId: 0),
            GroupMember(userId: 3, role: .member, joinedAfterMessageId: 20),
        ])
        let sut = await makeGroupSUT(groupInfo: groupInfo)
        storage.stored = [7: [2: 10, 3: 25]]
        sut.start()

        sut.beginObserving(conversationId: 7, isGroup: true)

        await yieldUntil { sut.coverage(conversationId: 7) != nil }
        XCTAssertEqual(sut.coverage(conversationId: 7)?.ranges, [.init(after: 0, upTo: 10), .init(after: 20, upTo: 25)])
    }

    /// Кейс: у группы есть мета, но состав ещё неизвестен.
    /// Ожидание: покрытия нет — две галочки без состава не показываются.
    func test_group_withoutInfo_hasNoCoverage() async {
        let sut = await makeGroupSUT(groupInfo: GroupInfoServiceMock())
        storage.stored = [7: [2: 10]]
        sut.start()

        sut.beginObserving(conversationId: 7, isGroup: true)

        await yieldUntil { sut.pointers(conversationId: 7) != nil }
        XCTAssertNil(sut.coverage(conversationId: 7))
    }

    /// Кейс: участник 3 вышел — пришёл новый состав без него; у группы есть мета.
    /// Ожидание: его указатель удалён из памяти и БД, покрытие пересчитано без него.
    func test_group_newInfoDropsDepartedMember() async {
        let groupInfo = GroupInfoServiceMock()
        let members = [GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0), GroupMember(userId: 2, role: .member, joinedAfterMessageId: 0)]
        groupInfo.infos[7] = GroupInfo(conversationId: 7, version: 1, members: members + [GroupMember(userId: 3, role: .member, joinedAfterMessageId: 0)])
        let sut = await makeGroupSUT(groupInfo: groupInfo)
        storage.stored = [7: [2: 5, 3: 12]]
        sut.start()
        sut.beginObserving(conversationId: 7, isGroup: true)
        await yieldUntil { sut.coverage(conversationId: 7)?.ranges == [.init(after: 0, upTo: 12)] }

        let info = GroupInfo(conversationId: 7, version: 2, members: members)
        groupInfo.infos[7] = info
        sut.groupInfoDidChange(info, isAuthoritative: true)

        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 5])
        XCTAssertEqual(sut.coverage(conversationId: 7)?.ranges, [.init(after: 0, upTo: 5)])
        await yieldUntil { [unowned self] in storage.stored[7] == [2: 5] }
    }

    /// Кейс: состав из БД (неавторитетный) без участника 3, у которого есть указатель.
    /// Ожидание: указатель не удаляется ни из памяти, ни из БД — сохранённый состав мог устареть.
    func test_group_storedInfoDoesNotDropMembers() async {
        let groupInfo = GroupInfoServiceMock()
        let members = [GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0), GroupMember(userId: 2, role: .member, joinedAfterMessageId: 0)]
        groupInfo.infos[7] = GroupInfo(conversationId: 7, version: 1, members: members)
        let sut = await makeGroupSUT(groupInfo: groupInfo)
        storage.stored = [7: [2: 5, 3: 12]]
        sut.start()
        sut.beginObserving(conversationId: 7, isGroup: true)
        await yieldUntil { sut.pointers(conversationId: 7) != nil }

        sut.groupInfoDidChange(GroupInfo(conversationId: 7, version: 1, members: members), isAuthoritative: false)

        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 5, 3: 12])
        await yieldTimes()
        XCTAssertEqual(storage.stored[7], [2: 5, 3: 12])
    }

    /// Кейс: группа наблюдается, состав неизвестен; затем состав пришёл.
    /// Ожидание: пока состава нет — «ждём состав» (лист «Кем прочитано» показывает загрузку), потом — нет.
    func test_group_isAwaitingGroupInfo() async {
        let groupInfo = GroupInfoServiceMock()
        let sut = await makeGroupSUT(groupInfo: groupInfo)
        sut.start()
        sut.beginObserving(conversationId: 7, isGroup: true)

        XCTAssertTrue(sut.isAwaitingGroupInfo(conversationId: 7))
        groupInfo.infos[7] = GroupInfo(conversationId: 7, version: 1, members: [GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0)])
        XCTAssertFalse(sut.isAwaitingGroupInfo(conversationId: 7))
    }

    /// Кейс: `memberRead` от пользователя 4, которого ещё нет в составе группы.
    /// Ожидание: указатель сохранён, но в покрытии не учитывается.
    func test_group_memberReadFromUnknownUser_isStoredButNotCounted() async {
        let groupInfo = GroupInfoServiceMock()
        groupInfo.infos[7] = GroupInfo(conversationId: 7, version: 1, members: [
            GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0),
            GroupMember(userId: 2, role: .member, joinedAfterMessageId: 0),
        ])
        let sut = await makeGroupSUT(groupInfo: groupInfo)
        storage.stored = [7: [2: 5]]
        sut.start()
        sut.beginObserving(conversationId: 7, isGroup: true)
        await yieldUntil { sut.coverage(conversationId: 7) != nil }

        await eventQueue.send(.memberRead(conversationId: 7, userId: 4, lastReadMessageId: 30))

        XCTAssertEqual(sut.pointers(conversationId: 7), [2: 5, 4: 30])
        XCTAssertEqual(sut.coverage(conversationId: 7)?.ranges, [.init(after: 0, upTo: 5)])
    }

}


extension MemberReadServiceTests {
    /// Сервис над моками теста с составом групп.
    /// - Parameter groupInfo: состав групп.
    fileprivate func makeGroupSUT(groupInfo: GroupInfoServiceMock) async -> MemberReadService {
        let session = SessionService(
            userDefaultsService: UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)),
            localStorageCleaner: LocalStorageCleanerMock()
        )
        let service = MemberReadService(
            conversationService: conversationService,
            storage: storage,
            eventQueue: eventQueue,
            sessionService: session,
            membership: membership,
            groupInfo: groupInfo
        )
        await session.restore()
        return service
    }
}

private extension MemberReadService {
    /// Верхняя граница покрытия личной переписки — прежний порог `readUpTo`.
    /// - Parameter conversationId: наблюдаемая переписка.
    func readUpTo(conversationId: Int) -> Int? {
        coverage(conversationId: conversationId)?.ranges.last?.upTo
    }
}
