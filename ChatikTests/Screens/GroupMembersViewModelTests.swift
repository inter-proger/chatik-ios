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
    private var conversationList: ConversationListServiceMock!
    private var userCache: UserCacheServiceMock!
    private var notifications: InAppNotificationServiceMock!
    private var sut: GroupMembersViewModel!

    override func setUp() async throws {
        try await super.setUp()
        groupInfo = GroupInfoServiceMock()
        groupService = GroupServiceMock()
        conversationList = ConversationListServiceMock()
        userCache = UserCacheServiceMock()
        notifications = InAppNotificationServiceMock()
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
            membership: conversationList,
            sessionService: sessionService,
            userCache: userCache,
            notifications: notifications
        )
    }

    /// Кейс: владелец — текущий пользователь 1, участники 2 «Борис», 3 «Анна» и 4 (не загружен).
    /// Ожидание: секция создателя — 1 («Вы»), участники по имени, незагруженный в конце.
    func test_content_sectionsAndOrder() {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2, 4, 3])

        let content = sut.content

        XCTAssertEqual(content?.owner?.id, 1)
        XCTAssertEqual(content?.owner?.isCurrentUser, true)
        XCTAssertEqual(content?.members.map(\.id), [3, 2, 4])
    }

    /// Кейс: передача прав — текущий пользователь владелец / участник; строка своя / чужая.
    /// Ожидание: меню только у владельца и не на своей строке.
    func test_canTransferOwnership_onlyOwnerOnOthers() {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        let rows = sut.content
        XCTAssertTrue(sut.canTransferOwnership(to: rows!.members[0]))
        XCTAssertFalse(sut.canTransferOwnership(to: rows!.owner!))

        groupInfo.infos[2] = .make(ownerId: 2, memberIds: [1])
        let memberRows = sut.content
        XCTAssertFalse(sut.canTransferOwnership(to: memberRows!.owner!))
    }

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
        sut.didSelectTransferOwnership(to: member)
        XCTAssertTrue(sut.isTransferConfirmationPresented)
        // Алерт закрывается до вызова кнопки — состояние уже сброшено, участник приходит из алерта.
        sut.isTransferConfirmationPresented = false

        sut.didConfirmTransfer(to: member)

        await yieldUntil { [unowned self] in !sut.isChangingOwner && !notifications.shown.isEmpty }
        XCTAssertEqual(groupService.changeOwnerRequests.map(\.newOwnerUserId), [2])
        XCTAssertEqual(groupInfo.applied, [newInfo])
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: GroupMembersStrings.ownershipTransferred)])
        XCTAssertNil(sut.pendingTransfer)
    }

    /// Кейс: передача прав ответила `5002`.
    /// Ожидание: ошибка показана, запрошена проверка членства.
    func test_transfer_conversationNotFound_verifiesMembership() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2])
        groupService.stubbedChangeOwner = .failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))
        let member = sut.content!.members[0]
        sut.didSelectTransferOwnership(to: member)

        sut.didConfirmTransfer(to: member)

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])
    }

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
