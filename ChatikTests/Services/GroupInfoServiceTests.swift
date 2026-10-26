//
//  GroupInfoServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class GroupInfoServiceTests: XCTestCase {
    private var groupService: GroupServiceMock!
    private var storage: GroupInfoStorageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var conversationList: ConversationListServiceMock!
    private var sut: GroupInfoService!

    override func setUp() async throws {
        try await super.setUp()
        groupService = GroupServiceMock()
        storage = GroupInfoStorageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        conversationList = ConversationListServiceMock()
        sut = GroupInfoService(
            groupService: groupService,
            storage: storage,
            eventQueue: eventQueue,
            membership: conversationList,
            removalMarks: conversationList
        )
    }

    // MARK: - Наблюдение

    /// Кейс: в БД состав версии 1; экран группы открыт, запрос `getInfo` отвечает версией 2 после чтения БД.
    /// Ожидание: сначала показан сохранённый состав, затем — ответ сервера; ответ записан в БД.
    func test_beginObserving_showsStoredThenResponse() async {
        storage.stored[12] = info(12, version: 1)
        let gate = Gate()
        groupService.fetchInfoGate = gate
        groupService.stubbedInfos = [.success(info(12, version: 2))]
        await start()

        sut.beginObserving(conversationId: 12)
        await yieldUntil { [unowned self] in sut.groupInfo(conversationId: 12)?.version == 1 && gate.isWaiting }
        gate.open()

        await yieldUntil { [unowned self] in sut.groupInfo(conversationId: 12)?.version == 2 }
        await yieldUntil { [unowned self] in storage.stored[12]?.version == 2 }
    }

    /// Кейс: известен состав версии 3, затем приходит ответ с версией 2 (собран раньше).
    /// Ожидание: состав не откатывается.
    func test_olderVersion_isIgnored() async {
        await start()
        sut.beginObserving(conversationId: 12)
        sut.apply(info(12, version: 3))

        sut.apply(info(12, version: 2))

        XCTAssertEqual(sut.groupInfo(conversationId: 12)?.version, 3)
    }

    /// Кейс: группы 12 и 13 — 12 наблюдается, 13 нет; пришёл `connected`.
    /// Ожидание: состав запрошен только у наблюдаемой группы (сверх запроса при открытии).
    func test_connected_refreshesOnlyObserved() async {
        groupService.stubbedInfos = [.success(info(12, version: 1))]
        await start()
        sut.beginObserving(conversationId: 12)
        await yieldUntil { [unowned self] in sut.groupInfo(conversationId: 12)?.version == 1 }

        await eventQueue.send(.connected)

        await yieldUntil { [unowned self] in groupService.fetchInfoRequests == [12, 12] }
    }

    /// Кейс: запрос состава уже в полёте, `refresh` и `snapshot` вызваны ещё раз.
    /// Ожидание: запрос один; `snapshot` получает его ответ.
    func test_refreshAndSnapshot_shareRequestInFlight() async throws {
        await start()
        let gate = Gate()
        groupService.fetchInfoGate = gate
        groupService.stubbedInfos = [.success(info(12, version: 4))]
        sut.refresh(conversationId: 12)
        await yieldUntil { gate.isWaiting }

        sut.refresh(conversationId: 12)
        let snapshot = Task { [sut] in try await sut!.snapshot(conversationId: 12) }
        await Task.yield()
        gate.open()

        let value = try await snapshot.value
        XCTAssertEqual(value.version, 4)
        XCTAssertEqual(groupService.fetchInfoRequests, [12])
    }

    /// Кейс: `snapshot` группы, состав которой есть только в БД.
    /// Ожидание: снимок из БД, без запроса.
    func test_snapshot_fromStorageWithoutRequest() async throws {
        storage.stored[12] = info(12, version: 5)
        await start()

        let value = try await sut.snapshot(conversationId: 12)

        XCTAssertEqual(value.version, 5)
        XCTAssertTrue(groupService.fetchInfoRequests.isEmpty)
    }

    /// Кейс: запрос состава ответил `5002`.
    /// Ожидание: запрошена проверка членства; у наблюдаемой группы отмечена ошибка.
    func test_fetchConversationNotFound_verifiesMembership() async {
        await start()
        groupService.stubbedInfos = [.failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))]

        sut.beginObserving(conversationId: 12)

        await yieldUntil { [unowned self] in conversationList.verifiedConversationIds == [12] }
        await yieldUntil { [unowned self] in sut.isRefreshFailed(conversationId: 12) }
    }

    // MARK: - События

    /// Кейс: `ownerChanged` для наблюдаемой группы 12, для сохранённой 13 и для чужой 14.
    /// Ожидание: применены 12 (на экране и в БД) и 13 (в БД); у 14 ничего не создано.
    func test_events_applyToObservedAndStoredOnly() async {
        storage.stored[13] = info(13, version: 1)
        await start()
        await yieldUntil { [unowned self] in !storage.stored.isEmpty }
        sut.beginObserving(conversationId: 12)

        await eventQueue.send(.group(.ownerChanged(conversationId: 12, newOwnerUserId: 2, groupInfo: info(12, version: 7))))
        await eventQueue.send(.group(.ownerChanged(conversationId: 13, newOwnerUserId: 2, groupInfo: info(13, version: 7))))
        await eventQueue.send(.group(.ownerChanged(conversationId: 14, newOwnerUserId: 2, groupInfo: info(14, version: 7))))

        XCTAssertEqual(sut.groupInfo(conversationId: 12)?.version, 7)
        await yieldUntil { [unowned self] in storage.stored[13]?.version == 7 }
        XCTAssertNil(storage.stored[14])
    }

    /// Кейс: `membersAdded` для добавленного по ненаблюдаемой группе; второе такое событие — не новее метки удаления.
    /// Ожидание: первое сохраняет состав безусловно; второе устарело и ничего не меняет.
    func test_membersAddedForMe_storesUnlessStale() async {
        conversationList.removedVersions = [13: 20]
        await start()

        await eventQueue.send(.group(.membersAdded(conversationId: 12, addedUserIds: [1], groupInfo: info(12, version: 2), changeVersion: 11)))
        await eventQueue.send(.group(.membersAdded(conversationId: 13, addedUserIds: [1], groupInfo: info(13, version: 2), changeVersion: 19)))

        await yieldUntil { [unowned self] in storage.stored[12]?.version == 2 }
        XCTAssertNil(sut.currentInfo(conversationId: 13))
        XCTAssertNil(storage.stored[13])
    }

    /// Кейс: ответ REST (`apply`) по группе, которая не наблюдается и не сохранена.
    /// Ожидание: состав сохраняется — ответ относится к группе, с которой работает пользователь.
    func test_applyREST_storesUnobservedGroup() async {
        await start()

        sut.apply(info(12, version: 2))

        await yieldUntil { [unowned self] in storage.stored[12]?.version == 2 }
        XCTAssertEqual(sut.currentInfo(conversationId: 12)?.version, 2)
    }

    /// Кейс: наблюдатель изменений; состав применён дважды с одной версией и затем с большей.
    /// Ожидание: наблюдатель получил два изменения — повтор той же версии его не будит.
    func test_observers_notifiedOnlyOnChange() async {
        await start()
        let observer = GroupInfoObserverSpy()
        sut.addObserver(observer)

        sut.apply(info(12, version: 2))
        sut.apply(info(12, version: 2))
        sut.apply(info(12, version: 3))

        XCTAssertEqual(observer.versions, [2, 3])
    }

    /// Кейс: пользователь больше не участник группы.
    /// Ожидание: состав удалён из памяти и БД.
    func test_conversationWasRemoved_deletesInfo() async {
        await start()
        sut.apply(info(12, version: 2))

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 12, name: nil, type: .group, reason: .removed, changeVersion: 1))

        XCTAssertNil(sut.currentInfo(conversationId: 12))
        XCTAssertEqual(storage.deletedConversationIds, [12])
        XCTAssertNil(storage.stored[12])
    }

    /// Кейс: выход из аккаунта.
    /// Ожидание: память очищена; применение во время выхода ничего не делает.
    func test_logout_resetsState() async {
        await start()
        sut.apply(info(12, version: 2))

        await sut.authServiceWillLogout()
        sut.apply(info(13, version: 1))

        XCTAssertNil(sut.currentInfo(conversationId: 12))
        XCTAssertNil(sut.currentInfo(conversationId: 13))
    }

    /// Кейс: экран открыт, в БД состав версии 1, сеть отвечает версией 2.
    /// Ожидание: наблюдатель получает состав из БД как неавторитетный, ответ сервера — как авторитетный.
    func test_observers_storedInfoIsNotAuthoritative() async {
        storage.stored[12] = info(12, version: 1)
        groupService.stubbedInfos = [.success(info(12, version: 2))]
        let observer = GroupInfoObserverSpy()
        sut.addObserver(observer)
        await start()

        sut.beginObserving(conversationId: 12)

        await yieldUntil { observer.versions == [1, 2] }
        XCTAssertEqual(observer.authoritative, [false, true])
    }

    /// Кейс: экран прочитал состав до `beginObserving` (первый `body`), затем начал наблюдение.
    /// Ожидание: появление группы в наблюдении будит читателя.
    func test_groupInfo_readBeforeObservingIsNotified() async {
        await start()
        let flag = ChangeFlag()
        withObservationTracking { _ = sut.groupInfo(conversationId: 12) } onChange: { flag.isSet = true }

        sut.beginObserving(conversationId: 12)

        XCTAssertTrue(flag.isSet)
    }

    /// Кейс: запрос состава отменён удалением группы, и сразу начат новый.
    /// Ожидание: завершение старого запроса не снимает новый — третий `refresh` не шлёт ещё один запрос.
    func test_cancelledFetch_doesNotClearNewer() async {
        await start()
        let gate = Gate()
        groupService.fetchInfoGate = gate
        sut.refresh(conversationId: 12)
        await yieldUntil { gate.isWaiting }
        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 12, name: nil, type: .group, reason: .removed, changeVersion: 1))
        sut.refresh(conversationId: 12)
        gate.open()
        await yieldTimes()

        sut.refresh(conversationId: 12)

        XCTAssertEqual(groupService.fetchInfoRequests, [12, 12])
    }

    // MARK: - Helpers

    /// Запускает сервис и дожидается чтения сохранённых групп.
    private func start() async {
        sut.start()
        await Task.yield()
        await Task.yield()
    }

    /// Состав из владельца — текущего пользователя.
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - version: версия состава.
    private func info(_ conversationId: Int, version: Int) -> GroupInfo {
        GroupInfo(conversationId: conversationId, version: version, members: [GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0)])
    }
}

/// Наблюдатель изменений состава: запоминает версии по порядку.
@MainActor
private final class GroupInfoObserverSpy: GroupInfoObserver {
    private(set) var versions: [Int] = []
    private(set) var authoritative: [Bool] = []

    func groupInfoDidChange(_ info: GroupInfo, isAuthoritative: Bool) {
        versions.append(info.version)
        authoritative.append(isAuthoritative)
    }
}

/// Флаг срабатывания Observation: `onChange` вызывается из любого потока, а читает тест после действия.
private final class ChangeFlag: @unchecked Sendable {
    var isSet = false
}
