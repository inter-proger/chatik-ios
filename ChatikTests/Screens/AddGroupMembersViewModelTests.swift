//
//  AddGroupMembersViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AddGroupMembersViewModelTests: XCTestCase {
    private var groupInfo: GroupInfoServiceMock!
    private var groupService: GroupServiceMock!
    private var usersService: UsersServiceMock!
    private var conversationList: ConversationListServiceMock!
    private var notifications: InAppNotificationServiceMock!
    private var navigator: GroupNavigatingMock!
    private var sut: AddGroupMembersViewModel!

    override func setUp() async throws {
        try await super.setUp()
        groupInfo = GroupInfoServiceMock()
        groupService = GroupServiceMock()
        usersService = UsersServiceMock()
        conversationList = ConversationListServiceMock()
        notifications = InAppNotificationServiceMock()
        navigator = GroupNavigatingMock()
        let sessionService = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: .stub), localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        sut = AddGroupMembersViewModel(
            conversationId: 2,
            groupInfo: groupInfo,
            groupService: groupService,
            usersService: usersService,
            membership: conversationList,
            sessionService: sessionService,
            userCache: UserCacheServiceMock(),
            notifications: notifications,
            navigator: navigator,
            searchDebounce: .zero
        )
    }

    /// Кейс: в группе владелец 1 и участник 2; выдача — пользователи 1–4.
    /// Ожидание: текущий пользователь исключён; 2 отмечен «в группе» и неактивен; «Не в группе» скрывает 2 без запроса.
    func test_rows_marksMembersAndFiltersWithoutRequest() async {
        await open(members: [2], users: [1, 2, 3, 4])

        XCTAssertEqual(sut.rows.map(\.id), [2, 3, 4])
        XCTAssertEqual(sut.rows.first?.isMember, true)
        XCTAssertEqual(sut.rows.first?.isDisabled, true)
        let requests = usersService.requests.count

        sut.filter = .notInGroup

        XCTAssertEqual(sut.rows.map(\.id), [3, 4])
        XCTAssertEqual(usersService.requests.count, requests)
    }

    /// Кейс: в группе 98 участников (ёмкость 2); выбраны двое, нажат третий; затем снят один.
    /// Ожидание: третьего выбрать нельзя, лимит достигнут, остальные неактивны; после снятия — снова можно.
    func test_selection_respectsCapacity() async {
        await open(members: Array(2...98), users: [100, 101, 102])
        let rows = sut.rows

        sut.didToggle(rows[0])
        sut.didToggle(rows[1])
        sut.didToggle(rows[2])

        XCTAssertEqual(sut.selectedIds, [100, 101])
        XCTAssertTrue(sut.isLimitReached)
        XCTAssertEqual(sut.rows[2].isDisabled, true)
        sut.didToggle(sut.rows[0])
        XCTAssertFalse(sut.isLimitReached)
    }

    /// Кейс: никого не выбрано, выбраны двое.
    /// Ожидание: заголовок «Добавить участников», затем «Добавить: 2»; кнопка активна только с выбором.
    func test_titleAndButton() async {
        await open(members: [], users: [3, 4])
        XCTAssertEqual(sut.title, AddGroupMembersStrings.title)
        XCTAssertFalse(sut.isAddButtonEnabled)

        sut.rows.forEach(sut.didToggle)

        XCTAssertEqual(sut.title, AddGroupMembersStrings.titleSelected(count: 2))
        XCTAssertTrue(sut.isAddButtonEnabled)
    }

    /// Кейс: выбраны 3 и 4; поисковый запрос сменился, и в новой выдаче их нет.
    /// Ожидание: выбор сохраняется.
    func test_selection_survivesSearch() async {
        await open(members: [], users: [3, 4])
        sut.rows.forEach(sut.didToggle)
        usersService.stubbedPages = [.success(page([5]))]

        sut.searchText = "Анна"
        await sut.searchTextDidChange()

        XCTAssertEqual(sut.selectedIds, [3, 4])
        XCTAssertEqual(sut.rows.map(\.id), [5])
    }

    /// Кейс: добавлены все выбранные.
    /// Ожидание: новый снимок (они «в группе»), выбор сброшен, состав применён, уведомление «Участники добавлены».
    func test_add_allAdded() async {
        await open(members: [], users: [3, 4])
        sut.rows.forEach(sut.didToggle)
        let info = GroupInfo.make(ownerId: 1, memberIds: [3, 4], version: 2)
        groupService.stubbedAddMembers = [.success(AddMembersResult(addedUserIds: [3, 4], notAddedUsersInfo: [], groupInfo: info))]

        sut.didTapAdd()

        await yieldUntil { [unowned self] in !sut.isAdding && !notifications.shown.isEmpty }
        XCTAssertEqual(groupService.addMembersRequests.first?.userIds, [3, 4])
        XCTAssertTrue(sut.selectedIds.isEmpty)
        XCTAssertEqual(sut.rows.map(\.isMember), [true, true])
        XCTAssertEqual(groupInfo.applied, [info])
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: AddGroupMembersStrings.allAdded)])
    }

    /// Кейс: из пяти не добавлены трое: двое — «уже в группе», один — «не найден».
    /// Ожидание: предупреждение «3 участника …» с действием; нажатие открывает попап с двумя секциями в порядке
    /// первого появления причины.
    func test_add_partialShowsWarningWithReport() async {
        await open(members: [], users: [3, 4, 5, 6, 7])
        sut.rows.forEach(sut.didToggle)
        let notAdded = [UserErrorInfo(userId: 5, errorCode: 5006), UserErrorInfo(userId: 6, errorCode: 4001), UserErrorInfo(userId: 7, errorCode: 5006)]
        groupService.stubbedAddMembers = [.success(AddMembersResult(addedUserIds: [3, 4], notAddedUsersInfo: notAdded, groupInfo: .make(memberIds: [3, 4, 5, 7], version: 2)))]

        sut.didTapAdd()

        await yieldUntil { [unowned self] in !notifications.shown.isEmpty }
        let notification = notifications.shown[0]
        XCTAssertEqual(notification.content, .warning(message: AddGroupMembersStrings.notAdded(count: 3)))
        notification.onTap?()
        let report = try? XCTUnwrap(sut.presentedNotAdded)
        let sections = report.map(sut.notAddedSections(for:)) ?? []
        XCTAssertEqual(sections.map(\.reason), [AddGroupMembersStrings.reasonAlreadyMember, AddGroupMembersStrings.reasonUserNotFound])
        XCTAssertEqual(sections.map { $0.users.map(\.id) }, [[5, 7], [6]])
    }

    /// Кейс: добавление ответило `5004` — права уже переданы.
    /// Ожидание: ошибка показана, состав обновляется, экран закрывается.
    func test_add_notOwner_closesScreen() async {
        await open(members: [], users: [3])
        sut.rows.forEach(sut.didToggle)
        groupService.stubbedAddMembers = [.failure(NetworkError.api(code: NetworkError.Code.groupOwnerOnly))]

        sut.didTapAdd()

        await yieldUntil { [unowned self] in !sut.isAdding }
        XCTAssertEqual(navigator.calls, ["pop"])
        XCTAssertEqual(groupInfo.refreshIds, [2])
        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorGroupOwnerOnly])
    }

    /// Кейс: «Не в группе», первая страница — только участники, у выдачи есть продолжение.
    /// Ожидание: следующая страница запрошена без прокрутки, её пользователи показаны.
    func test_filter_fewVisibleRows_loadsNextPage() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [2, 3])
        await sut.loadSnapshot()
        sut.filter = .notInGroup
        usersService.stubbedPages = [.success(page([2, 3], hasNext: true)), .success(page([4]))]

        await sut.loadFirstPage()

        await yieldUntil { [unowned self] in sut.rows.map(\.id) == [4] }
        XCTAssertEqual(usersService.requests.count, 2)
    }

    /// Кейс: снимок состава не загрузился (`5002`), затем повтор успешен.
    /// Ожидание: ошибка снимка отмечена и запрошена проверка членства; повтор загружает снимок.
    func test_snapshot_failureThenRetry() async {
        await sut.loadSnapshot()
        XCTAssertTrue(sut.isSnapshotFailed)
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])

        groupInfo.infos[2] = .make()
        await sut.loadSnapshot()

        XCTAssertFalse(sut.isSnapshotFailed)
        XCTAssertNotNil(sut.snapshot)
    }

    /// Кейс: добавление ответило `5002`.
    /// Ожидание: ошибка показана, запрошена проверка членства, экран не закрывается сам.
    func test_add_conversationNotFound_verifiesMembership() async {
        await open(members: [], users: [3])
        sut.rows.forEach(sut.didToggle)
        groupService.stubbedAddMembers = [.failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))]

        sut.didTapAdd()

        await yieldUntil { [unowned self] in !sut.isAdding }
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])
        XCTAssertTrue(navigator.calls.isEmpty)
    }

    // MARK: - Helpers

    /// Открывает экран: снимок с владельцем 1 и участниками, первая страница выдачи.
    /// - Parameters:
    ///   - members: участники, кроме владельца.
    ///   - users: id пользователей выдачи.
    private func open(members: [Int], users: [Int]) async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: members)
        usersService.stubbedPages = [.success(page(users))]
        await sut.loadSnapshot()
        await sut.loadFirstPage()
    }

    /// Страница пользователей.
    /// - Parameters:
    ///   - ids: пользователи.
    ///   - hasNext: есть ли продолжение.
    private func page(_ ids: [Int], hasNext: Bool = false) -> UsersPage {
        UsersPage(users: ids.map { User(userId: $0, login: "u\($0)", name: "Пользователь \($0)", avatar: nil) }, nextMaxId: ids.last, hasNext: hasNext)
    }
}
