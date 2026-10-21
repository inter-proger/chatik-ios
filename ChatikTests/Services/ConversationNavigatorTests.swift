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
}
