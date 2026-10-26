//
//  GroupOptionsViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class GroupOptionsViewModelTests: XCTestCase {
    private var conversationList: ConversationListServiceMock!
    private var groupInfo: GroupInfoServiceMock!
    private var groupService: GroupServiceMock!
    private var notifications: InAppNotificationServiceMock!
    private var navigator: GroupNavigatingMock!
    private var sessionService: SessionService!
    private var sut: GroupOptionsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        conversationList = ConversationListServiceMock()
        groupInfo = GroupInfoServiceMock()
        groupService = GroupServiceMock()
        notifications = InAppNotificationServiceMock()
        navigator = GroupNavigatingMock()
        sessionService = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: .stub), localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        sut = GroupOptionsViewModel(
            conversation: .groupStub,
            conversationList: conversationList,
            groupInfo: groupInfo,
            groupService: groupService,
            sessionService: sessionService,
            notifications: notifications,
            navigator: navigator
        )
    }

    /// Кейс: группы нет в списке; затем она появилась в списке с другим названием.
    /// Ожидание: сначала показан снимок из маршрута, затем — версия из списка.
    func test_conversation_fallsBackToSnapshot() {
        XCTAssertEqual(sut.title, "Команда")

        conversationList.conversations = [Conversation.groupStub.with(name: "Новое", updatedInfoAt: .stub(1))]

        XCTAssertEqual(sut.title, "Новое")
    }

    /// Кейс: текст алерта выхода для участника, владельца с другими участниками и единственного участника.
    /// Ожидание: базовый текст; с добавкой о передаче прав; с добавкой о пустой группе.
    func test_leaveMessage_byCase() {
        let cases: [(info: GroupInfo, expected: String)] = [
            (.make(ownerId: 5, memberIds: [1]), GroupOptionsStrings.leaveMessage),
            (.make(ownerId: 1, memberIds: [5]), GroupOptionsStrings.leaveMessageOwner),
            (.make(ownerId: 1), GroupOptionsStrings.leaveMessageLastMember),
        ]

        for (info, expected) in cases {
            groupInfo.infos[2] = info
            XCTAssertEqual(sut.leaveMessage, expected)
        }
    }

    /// Кейс: «Добавить участников» и «Покинуть группу» при неизвестном составе, у владельца и у участника.
    /// Ожидание: без состава — ни добавления, ни выхода; добавлять может только владелец.
    func test_rights_byRoleAndInfo() {
        XCTAssertFalse(sut.canAddMembers)
        XCTAssertFalse(sut.isLeaveEnabled)

        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [5])
        XCTAssertTrue(sut.canAddMembers)
        XCTAssertTrue(sut.isLeaveEnabled)

        groupInfo.infos[2] = .make(ownerId: 5, memberIds: [1])
        XCTAssertFalse(sut.canAddMembers)
    }

    /// Кейс: выход подтверждён, сервер ответил меткой.
    /// Ожидание: выход отмечен в полёте и снят, метка применена, переход к списку и уведомление «Вы покинули группу».
    func test_leave_success() async {
        groupInfo.infos[2] = .make(ownerId: 1)
        let removal = ConversationRemoval(removedConversation: RemovedConversation(conversationId: 2, changeVersion: 11), totalUnreadCount: 0)
        groupService.stubbedLeave = .success(removal)

        sut.didConfirmLeave()

        await yieldUntil { [unowned self] in !sut.isLeaving }
        XCTAssertEqual(conversationList.leavingCalls, ["begin 2", "end 2"])
        XCTAssertEqual(conversationList.appliedLeaves, [removal])
        XCTAssertEqual(navigator.calls, ["root"])
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: GroupOptionsStrings.left)])
    }

    /// Кейс: пока идёт выход, нажаты «Участники», «Добавить» и ещё раз «Выйти».
    /// Ожидание: экран заблокирован — переходов нет, запрос один.
    func test_leave_blocksActionsDuringRequest() async {
        groupInfo.infos[2] = .make(ownerId: 1, memberIds: [5])
        let gate = Gate()
        groupService.actionGate = gate

        sut.didConfirmLeave()
        await yieldUntil { gate.isWaiting }
        sut.didTapMembers()
        sut.didTapAddMembers()
        sut.didConfirmLeave()

        XCTAssertTrue(sut.isLeaving)
        XCTAssertTrue(navigator.calls.isEmpty)
        XCTAssertEqual(groupService.leaveRequests, [2])
        gate.open()
        await yieldUntil { [unowned self] in !sut.isLeaving }
    }

    /// Кейс: выход ответил `5002` — пользователь уже не участник.
    /// Ожидание: запрошена проверка членства, текста ошибки нет — о потере доступа сообщит она.
    func test_leave_conversationNotFound_verifiesWithoutError() async {
        groupInfo.infos[2] = .make(ownerId: 1)
        groupService.stubbedLeave = .failure(NetworkError.api(code: NetworkError.Code.conversationNotFound))

        sut.didConfirmLeave()

        await yieldUntil { [unowned self] in !sut.isLeaving }
        XCTAssertEqual(conversationList.verifiedConversationIds, [2])
        XCTAssertTrue(notifications.shownErrors.isEmpty)
    }

    /// Кейс: выход не удался (сети нет).
    /// Ожидание: ошибка показана, экран разблокирован, к списку не переходим.
    func test_leave_failureShowsErrorAndUnlocks() async {
        groupInfo.infos[2] = .make(ownerId: 1)
        groupService.stubbedLeave = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        sut.didConfirmLeave()

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertFalse(sut.isLeaving)
        XCTAssertTrue(navigator.calls.isEmpty)
        XCTAssertTrue(conversationList.appliedLeaves.isEmpty)
    }
}
