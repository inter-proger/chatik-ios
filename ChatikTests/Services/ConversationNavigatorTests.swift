//
//  ConversationNavigatorTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ConversationNavigatorTests: XCTestCase {
    private var notifications: InAppNotificationServiceMock!
    private var conversationList: ConversationListServiceMock!
    private var sut: ConversationNavigator!

    override func setUp() async throws {
        try await super.setUp()
        notifications = InAppNotificationServiceMock()
        conversationList = ConversationListServiceMock()
        conversationList.conversations = [.singleStub, .groupStub]
        sut = ConversationNavigator(notifications: notifications, conversationList: conversationList)
    }

    /// Кейс: два роутера в разных активных сценах, во втором открыта переписка 1.
    /// Ожидание: переписка 1 открыта, переписка 2 — нет.
    func test_isConversationOpen_checksAllScenes() {
        let firstScene = UUID()
        let secondScene = UUID()
        let first = ConversationOpeningMock()
        let second = ConversationOpeningMock()
        second.openedConversationId = 1
        _ = sut.register(first, sceneId: firstScene)
        _ = sut.register(second, sceneId: secondScene)
        notifications.setActive(true, sceneId: firstScene)
        notifications.setActive(true, sceneId: secondScene)

        XCTAssertTrue(sut.isConversationOpen(1))
        XCTAssertFalse(sut.isConversationOpen(2))
    }

    /// Кейс: переписка 1 открыта в сцене, которая ушла в фон; активна другая сцена.
    /// Ожидание: переписка не считается открытой — уведомления о ней показываются.
    func test_isConversationOpen_inactiveScene_returnsFalse() {
        let backgroundScene = UUID()
        let activeScene = UUID()
        let router = ConversationOpeningMock()
        router.openedConversationId = 1
        _ = sut.register(router, sceneId: backgroundScene)
        _ = sut.register(ConversationOpeningMock(), sceneId: activeScene)
        notifications.setActive(true, sceneId: backgroundScene)
        notifications.setActive(false, sceneId: backgroundScene)
        notifications.setActive(true, sceneId: activeScene)

        XCTAssertFalse(sut.isConversationOpen(1))
    }

    /// Кейс: переписка 1 открыта в роутере без сцены (превью).
    /// Ожидание: переписка считается открытой.
    func test_isConversationOpen_unknownScene_returnsTrue() {
        let router = ConversationOpeningMock()
        router.openedConversationId = 1
        _ = sut.register(router, sceneId: nil)

        XCTAssertTrue(sut.isConversationOpen(1))
    }

    /// Кейс: роутер с открытой перепиской снят с регистрации.
    /// Ожидание: переписка больше не считается открытой.
    func test_unregister_removesRouter() {
        let router = ConversationOpeningMock()
        router.openedConversationId = 1
        let token = sut.register(router, sceneId: nil)

        sut.unregister(token)

        XCTAssertFalse(sut.isConversationOpen(1))
    }

    /// Кейс: два роутера; уведомления показываются в сцене первого; нажатие на уведомление о переписке 2.
    /// Ожидание: переписка из списка открыта в роутере сцены показа, второй роутер не тронут.
    func test_openConversation_usesPresentingScene() {
        let presentingScene = UUID()
        let first = ConversationOpeningMock()
        let second = ConversationOpeningMock()
        _ = sut.register(first, sceneId: presentingScene)
        _ = sut.register(second, sceneId: UUID())
        notifications.setActive(true, sceneId: presentingScene)

        sut.openConversation(id: 2)

        XCTAssertEqual(first.opened, [.groupStub])
        XCTAssertTrue(second.opened.isEmpty)
    }

    /// Кейс: роутера сцены показа нет (сцена неизвестна).
    /// Ожидание: переписка открыта в последнем зарегистрированном роутере.
    func test_openConversation_withoutPresentingRouter_usesLastRegistered() {
        let first = ConversationOpeningMock()
        let second = ConversationOpeningMock()
        _ = sut.register(first, sceneId: nil)
        _ = sut.register(second, sceneId: nil)

        sut.openConversation(id: 1)

        XCTAssertTrue(first.opened.isEmpty)
        XCTAssertEqual(second.opened, [.singleStub])
    }

    /// Кейс: переписки нет в списке (например, после выхода из аккаунта).
    /// Ожидание: ничего не открывается.
    func test_openConversation_unknownConversation_doesNothing() {
        let router = ConversationOpeningMock()
        _ = sut.register(router, sceneId: nil)

        sut.openConversation(id: 99)

        XCTAssertTrue(router.opened.isEmpty)
    }

    // MARK: - Удаление переписки

    /// Кейс: удалили из группы 2, она открыта в одной из двух сцен.
    /// Ожидание: экраны группы закрыты в обеих сценах (закрытие запрошено у каждого роутера); показано уведомление
    /// «больше не участник» с названием группы.
    func test_conversationWasRemoved_openGroup_closesAndNotifies() async {
        let first = ConversationOpeningMock()
        let second = ConversationOpeningMock()
        second.openedConversationId = 2
        _ = sut.register(first, sceneId: UUID())
        _ = sut.register(second, sceneId: UUID())

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 2, name: "Команда", type: .group, reason: .removed, changeVersion: 1))

        XCTAssertEqual(first.closed, [2])
        XCTAssertEqual(second.closed, [2])
        XCTAssertNil(second.openedConversationId)
        XCTAssertEqual(notifications.shown.map(\.content), [.info(message: InAppNotificationStrings.noLongerMember(groupName: "Команда"))])
    }

    /// Кейс: открыта личная переписка, и проверка членства её удалила.
    /// Ожидание: экран закрыт, уведомления нет — текст про группу к ней не подходит.
    func test_conversationWasRemoved_single_closesWithoutNotification() async {
        let router = ConversationOpeningMock()
        router.openedConversationId = 1
        _ = sut.register(router, sceneId: UUID())

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 1, name: nil, type: .single, reason: .lostAccess, changeVersion: 1))

        XCTAssertEqual(router.closed, [1])
        XCTAssertTrue(notifications.shown.isEmpty)
    }


    /// Кейс: группа открыта, но пользователь вышел сам (`.left`); другая группа удалена, но нигде не открыта.
    /// Ожидание: уведомлений нет — о своём выходе сообщает экран опций, о неоткрытой группе — не нужно.
    func test_conversationWasRemoved_leftOrNotOpen_doesNotNotify() async {
        let router = ConversationOpeningMock()
        router.openedConversationId = 2
        _ = sut.register(router, sceneId: UUID())

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 2, name: "Команда", type: .group, reason: .left, changeVersion: 1))
        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 3, name: nil, type: .group, reason: .removed, changeVersion: 1))

        XCTAssertTrue(notifications.shown.isEmpty)
    }
}
