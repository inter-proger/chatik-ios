//
//  GroupMembersViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class GroupMembersViewModelTests: XCTestCase {
    private var groupInfo: GroupInfoServiceMock!
    private var groupService: GroupServiceMock!
    private var conversationService: ConversationServiceMock!
    private var conversationList: ConversationListServiceMock!
    private var userCache: UserCacheServiceMock!
    private var notifications: InAppNotificationServiceMock!
    private var navigator: GroupNavigatingMock!
    private var sut: GroupMembersViewModel!

    override func setUp() async throws {
        try await super.setUp()
        groupInfo = GroupInfoServiceMock()
        groupService = GroupServiceMock()
        conversationService = ConversationServiceMock()
        conversationList = ConversationListServiceMock()
        userCache = UserCacheServiceMock()
        notifications = InAppNotificationServiceMock()
        navigator = GroupNavigatingMock()
        let sessionService = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: .stub), localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        userCache.users = [
            1: .loaded(User(userId: 1, login: "ivan", name: "Иван", avatar: nil)),
            2: .loaded(User(userId: 2, login: "boris", name: "Борис", avatar: nil)),
            3: .loaded(User(userId: 3, login: "anna", name: "Анна", avatar: nil)),
        ]
        sut = GroupMembersViewModel(
            conversationId: 2,
            groupInfo: groupInfo,
            groupService: groupService,
            conversationService: conversationService,
            conversationList: conversationList,
            sessionService: sessionService,
            userCache: userCache,
            notifications: notifications,
            navigator: navigator
        )
    }

    // MARK: - Состав

    /// Кейс: владелец — текущий пользователь 1, участники 2 «Борис», 3 «Анна» и 4 (не загружен).
    /// Ожидание: секция создателя — 1 («Вы»), участники по имени, незагруженный в конце.
    func test_content_sectionsAndOrder() {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2, 4, 3])

        let content = sut.content

        XCTAssertEqual(content?.owner?.id, 1)
        XCTAssertEqual(content?.owner?.isCurrentUser, true)
        XCTAssertEqual(content?.members.map(\.id), [3, 2, 4])
    }

    // MARK: - Меню

    /// Кейс: меню у своей строки, у участника, когда текущий пользователь — создатель, и когда он участник.
    /// Ожидание: своя строка — без меню; создатель видит все три действия; участник — только «Личный диалог».
    func test_actions_byRoleAndRow() {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let ownerView = sut.content!
        XCTAssertEqual(sut.actions(for: ownerView.owner!), [])
        XCTAssertEqual(sut.actions(for: ownerView.members[0]), [.directChat, .transferOwnership, .remove])

        groupInfo.infos[2] = .make(ownerId: 2, memberIds: [1])
        let memberView = sut.content!
        XCTAssertEqual(sut.actions(for: memberView.owner!), [.directChat])
    }

    /// Кейс: идёт запрос с экрана (создаётся личный диалог); «Личный диалог» выбран повторно.
    /// Ожидание: меню не показывается ни у кого, второй запрос не уходит.
    func test_actions_hiddenDuringRequest() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2, 3])
        let gate = Gate()
        conversationService.onRequest = { await gate.wait() }
        conversationService.stubbedConversation = .success(.singleStub)
        let rows = sut.content!.members

        sut.didSelect(.directChat, for: rows[0])
        await yieldUntil { gate.isWaiting }
        sut.didSelect(.directChat, for: rows[0])

        XCTAssertEqual(sut.actions(for: rows[1]), [])
        XCTAssertEqual(sut.openingChatMemberId, rows[0].id)
        XCTAssertEqual(conversationService.createSingleUserIds, [rows[0].id])
        gate.open()
        await yieldUntil { [unowned self] in !sut.isPerformingAction }
    }

    // MARK: - Личный диалог

    /// Кейс: «Личный диалог» с участником 2; сервер вернул переписку (созданную или уже существующую).
    /// Ожидание: запрос ушёл с id участника, переписка добавлена в список и открыта вместо стека экранов.
    func test_directChat_createsAppliesAndOpens() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        conversationService.stubbedConversation = .success(.singleStub)

        sut.didSelect(.directChat, for: sut.content!.members[0])

        await yieldUntil { [unowned self] in !sut.isPerformingAction }
        XCTAssertEqual(conversationService.createSingleUserIds, [2])
        XCTAssertEqual(conversationList.applied, [.singleStub])
        XCTAssertEqual(navigator.calls, ["open \(Conversation.singleStub.conversationId)"])
    }

    /// Кейс: создание личного диалога не удалось (сети нет).
    /// Ожидание: ошибка показана, ничего не открыто, меню снова доступно.
    func test_directChat_failureShowsError() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        conversationService.stubbedConversation = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        let member = sut.content!.members[0]

        sut.didSelect(.directChat, for: member)

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertTrue(navigator.calls.isEmpty)
        XCTAssertEqual(sut.actions(for: member), [.directChat, .transferOwnership, .remove])
    }

    /// Кейс: во время создания личного диалога пользователь ушёл с экрана, затем пришёл ответ.
    /// Ожидание: переписка попала в список, но не открыта; ошибки нет.
    func test_directChat_leftScreen_doesNotOpen() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let gate = Gate()
        conversationService.onRequest = { await gate.wait() }
        conversationService.stubbedConversation = .success(.singleStub)

        sut.didSelect(.directChat, for: sut.content!.members[0])
        await yieldUntil { gate.isWaiting }
        sut.didDisappear()
        gate.open()

        await yieldUntil { [unowned self] in !sut.isPerformingAction }
        XCTAssertEqual(conversationList.applied, [.singleStub])
        XCTAssertTrue(navigator.calls.isEmpty)
        XCTAssertTrue(notifications.shownErrors.isEmpty)
    }

    // MARK: - Передача прав

    /// Кейс: права переданы участнику 2; алерт закрылся (состояние сброшено) до нажатия «ОК».
    /// Ожидание: запрос всё равно ушёл — участник приходит из алерта; новый состав применён, уведомление
    /// «Права создателя переданы».
    func test_transfer_success() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let newInfo = GroupInfo(conversationId: 2, version: 2, members: [
            GroupMember(userId: 1, role: .member, joinedAfterMessageId: 0),
            GroupMember(userId: 2, role: .owner, joinedAfterMessageId: 0),
        ])
        groupService.stubbedChangeOwner = .success(newInfo)
        let member = sut.content!.members[0]
        sut.didSelect(.transferOwnership, for: member)
        XCTAssertTrue(sut.isTransferConfirmationPresented)
        sut.isTransferConfirmationPresented = false

        sut.didConfirmTransfer(to: member)

        await yieldUntil { [unowned self] in !sut.isPerformingAction && !notifications.shown.isEmpty }
        XCTAssertEqual(groupService.changeOwnerRequests.map(\.newOwnerUserId), [2])
        XCTAssertEqual(groupInfo.applied, [newInfo])
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: GroupMembersStrings.ownershipTransferred)])
    }

    /// Кейс: передача прав ответила `5002`.
    /// Ожидание: проверка членства запрошена, отдельного уведомления об ошибке нет.
    func test_transfer_conversationNotFound_verifiesMembership() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        groupService.stubbedChangeOwner = .failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))

        sut.didConfirmTransfer(to: sut.content!.members[0])

        await yieldUntil { [unowned self] in !sut.isPerformingAction }
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])
        XCTAssertTrue(notifications.shownErrors.isEmpty)
    }

    /// Кейс: передача прав ответила `5004` — права уже переданы с другого устройства.
    /// Ожидание: ошибка показана, состав запрошен заново.
    func test_transfer_notOwner_refreshesInfo() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        groupService.stubbedChangeOwner = .failure(NetworkError.api(code: NetworkError.Code.groupOwnerOnly))

        sut.didConfirmTransfer(to: sut.content!.members[0])

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorGroupOwnerOnly])
        XCTAssertEqual(groupInfo.refreshIds, [2])
    }

    /// Кейс: пока алерт подтверждения открыт, текущий пользователь перестал быть создателем; нажато подтверждение.
    /// Ожидание: запросы не уходят, показана ошибка «только создатель».
    func test_confirm_afterRoleLost_showsError() {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2, 3])
        let member = sut.content!.members[0]
        groupInfo.infos[2] = .make(ownerId: 3, memberIds: [1, 2])

        sut.didConfirmTransfer(to: member)
        sut.didConfirmRemoval(of: member)

        XCTAssertTrue(groupService.changeOwnerRequests.isEmpty)
        XCTAssertTrue(groupService.removeMembersRequests.isEmpty)
        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorGroupOwnerOnly, CommonStrings.errorGroupOwnerOnly])
    }

    // MARK: - Исключение

    /// Кейс: исключение участника 2 подтверждено (алерт успел сбросить состояние).
    /// Ожидание: запрос с id участника, новый состав применён, уведомление «Участник исключён из группы».
    func test_remove_success() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let newInfo = GroupInfo.make(ownerId: 1, version: 2)
        groupService.stubbedRemoveMembers = .success(RemoveMembersResult(removedUserIds: [2], notRemovedUsersInfo: [], groupInfo: newInfo))
        let member = sut.content!.members[0]
        sut.didSelect(.remove, for: member)
        XCTAssertTrue(sut.isRemoveConfirmationPresented)
        sut.isRemoveConfirmationPresented = false

        sut.didConfirmRemoval(of: member)

        await yieldUntil { [unowned self] in !sut.isPerformingAction && !notifications.shown.isEmpty }
        XCTAssertEqual(groupService.removeMembersRequests.map(\.userIds), [[2]])
        XCTAssertEqual(groupInfo.applied, [newInfo])
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: GroupMembersStrings.memberRemoved)])
    }

    /// Кейс: участник уже вышел сам — сервер вернул его в `notRemovedUsersInfo` с кодом 5007.
    /// Ожидание: состав всё равно применён, показана ошибка по коду.
    func test_remove_notRemoved_showsReason() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let newInfo = GroupInfo.make(ownerId: 1, version: 2)
        groupService.stubbedRemoveMembers = .success(RemoveMembersResult(
            removedUserIds: [],
            notRemovedUsersInfo: [UserErrorInfo(userId: 2, errorCode: NetworkError.Code.notGroupMember)],
            groupInfo: newInfo
        ))

        sut.didConfirmRemoval(of: sut.content!.members[0])

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertEqual(groupInfo.applied, [newInfo])
        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorNotGroupMember])
    }

    /// Кейс: исключение ответило `5004` — права уже переданы.
    /// Ожидание: ошибка показана, состав запрошен заново.
    func test_remove_notOwner_refreshesInfo() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        groupService.stubbedRemoveMembers = .failure(NetworkError.api(code: NetworkError.Code.groupOwnerOnly))

        sut.didConfirmRemoval(of: sut.content!.members[0])

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorGroupOwnerOnly])
        XCTAssertEqual(groupInfo.refreshIds, [2])
    }

    /// Кейс: исключение ответило `5002` — текущего пользователя уже нет в группе.
    /// Ожидание: проверка членства запрошена, отдельного уведомления об ошибке нет.
    func test_remove_conversationNotFound_verifiesMembership() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        groupService.stubbedRemoveMembers = .failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))

        sut.didConfirmRemoval(of: sut.content!.members[0])

        await yieldUntil { [unowned self] in !sut.isPerformingAction }
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])
        XCTAssertTrue(notifications.shownErrors.isEmpty)
    }

    // MARK: - Загрузка

    /// Кейс: состав неизвестен, запрос не удался; нажат «Повторить», затем pull-to-refresh.
    /// Ожидание: ошибка видна; оба действия запрашивают состав.
    func test_failedThenRetryAndReload() async {
        groupInfo.failedRefreshIds = [2]
        XCTAssertNil(sut.content)
        XCTAssertTrue(sut.isFailed)

        sut.didTapRetry()
        await sut.reload()

        XCTAssertEqual(groupInfo.refreshIds, [2, 2])
    }

    /// Кейс: в составе участник 4, которого нет в кэше пользователей.
    /// Ожидание: он запрашивается один раз, повторный вызов не шлёт второй запрос, пока первый идёт.
    func test_loadMissingUsers_requestsOnce() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [4])

        sut.loadMissingUsers()
        sut.loadMissingUsers()

        await yieldUntil { [unowned self] in !userCache.loadRequests.isEmpty }
        XCTAssertEqual(userCache.loadRequests, [[4]])
    }
}
