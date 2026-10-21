//
//  MessageNotificationServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageNotificationServiceTests: XCTestCase {
    /// Текущий пользователь.
    private let currentUser = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
    /// Собеседник личной переписки `Conversation.singleStub`.
    private let anna = User(userId: 2, login: "anna", name: "Anna", avatar: nil)
    private var queue: RealtimeEventQueueMock!
    private var conversationList: ConversationListServiceMock!
    private var userCache: UserCacheServiceMock!
    private var navigator: ConversationNavigatorMock!
    private var notifications: InAppNotificationServiceMock!
    private var sleepController: SleepController!
    /// Загрузки пользователей, остановленные тестом; пустой — загрузка завершается сразу.
    private var loadGates: [Gate] = []
    private var holdsLoads = false
    private var sut: MessageNotificationService!

    override func setUp() async throws {
        try await super.setUp()
        queue = RealtimeEventQueueMock()
        conversationList = ConversationListServiceMock()
        conversationList.conversations = [.singleStub, .groupStub]
        userCache = UserCacheServiceMock()
        userCache.users = [2: .loaded(anna)]
        loadGates = []
        holdsLoads = false
        userCache.onLoad = { [unowned self] in
            guard holdsLoads else { return }
            let gate = Gate()
            loadGates.append(gate)
            await gate.wait()
        }
        navigator = ConversationNavigatorMock()
        notifications = InAppNotificationServiceMock()
        sleepController = SleepController()
        let session = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: currentUser), localStorageCleaner: LocalStorageCleanerMock())
        await session.restore()
        sut = MessageNotificationService(
            eventQueue: queue,
            sessionService: session,
            conversationList: conversationList,
            userCache: userCache,
            navigator: navigator,
            notifications: notifications,
            sleep: { [sleepController] in try await sleepController!.sleep($0) }
        )
        sut.start()
    }

    override func tearDown() async throws {
        loadGates.forEach { $0.open() }
        sut = nil
        try await super.tearDown()
    }

    /// Кейс: в неоткрытую личную переписку пришло сообщение собеседника, он есть в кэше.
    /// Ожидание: показано уведомление с именем собеседника и текстом.
    func test_received_fromOtherUser_showsNotification() async {
        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2, text: "Привет")))

        await yieldUntil { notifications.shownMessages.count == 1 }
        let model = notifications.shownMessages.first
        XCTAssertEqual(model?.conversationId, 1)
        XCTAssertEqual(model?.messageId, 7)
        XCTAssertEqual(model?.title, "Anna")
        XCTAssertEqual(model.map { String($0.text.characters) }, "Привет")
    }

    /// Кейс: в группу пришло сообщение участника.
    /// Ожидание: заголовок — название группы, текст с именем отправителя.
    func test_received_inGroup_showsSenderPrefix() async {
        await queue.send(.received(.make(id: 7, conversationId: 2, senderId: 2, text: "Созвон")))

        await yieldUntil { notifications.shownMessages.count == 1 }
        XCTAssertEqual(notifications.shownMessages.first?.title, "Команда")
        XCTAssertEqual(notifications.shownMessages.first.map { String($0.text.characters) }, "Anna: Созвон")
    }

    /// Кейс: события, которые не дают уведомления: своё сообщение (с другого устройства), правка, новая переписка,
    /// подключение.
    /// Ожидание: уведомлений нет.
    func test_ignoredEvents_showNothing() async {
        let events: [RealtimeEvent] = [
            .received(.make(id: 7, conversationId: 1, senderId: 1)),
            .edited(.make(id: 7, conversationId: 1, senderId: 2)),
            .conversationCreated(.singleStub),
            .connected,
        ]

        for event in events {
            await queue.send(event)
        }

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: сообщение пришло в переписку, открытую в одной из сцен.
    /// Ожидание: уведомления нет.
    func test_received_inOpenConversation_showsNothing() async {
        navigator.openConversationIds = [1]

        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: переписки из события нет в списке (её загрузка не удалась).
    /// Ожидание: уведомления нет — по нажатию нечего открыть.
    func test_received_conversationMissing_showsNothing() async {
        await queue.send(.received(.make(id: 7, conversationId: 99, senderId: 2)))

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: отправителя нет в кэше; обработчик события возвращается, пока загрузка идёт; затем отправитель загрузился.
    /// Ожидание: обработчик не ждёт загрузки; уведомление показано после неё с именем отправителя.
    func test_received_pendingSender_showsAfterLoad() async {
        userCache.users = [:]
        holdsLoads = true

        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))

        await yieldUntil { loadGates.count == 1 }
        XCTAssertTrue(notifications.shown.isEmpty)
        XCTAssertEqual(userCache.loadRequests, [[2]])
        userCache.users = [2: .loaded(anna)]
        loadGates[0].open()
        await yieldUntil { notifications.shownMessages.count == 1 }
        XCTAssertEqual(notifications.shownMessages.first?.title, "Anna")
    }

    /// Кейс: отправитель не загрузился за `userWaitTimeout`.
    /// Ожидание: уведомление показано с заглушкой вместо имени.
    func test_received_senderTimeout_showsPlaceholder() async {
        userCache.users = [:]
        holdsLoads = true
        sleepController.allow(MessageNotificationService.userWaitTimeout)

        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))

        await yieldUntil { notifications.shownMessages.count == 1 }
        XCTAssertEqual(notifications.shownMessages.first?.title, InAppNotificationStrings.messageUnknownSender)
    }

    /// Кейс: отправитель не загрузился за `userWaitTimeout`, уведомление показано с заглушкой; затем загрузка
    /// завершилась.
    /// Ожидание: загрузка не отменена тайм-аутом — её результат нужен списку и ленте.
    func test_received_senderTimeout_doesNotCancelLoad() async {
        userCache.users = [:]
        let gate = Gate()
        var isLoadCancelled: Bool?
        userCache.onLoad = {
            await gate.wait()
            isLoadCancelled = Task.isCancelled
        }
        sleepController.allow(MessageNotificationService.userWaitTimeout)

        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))
        await yieldUntil { notifications.shownMessages.count == 1 && gate.isWaiting }
        gate.open()

        await yieldUntil { isLoadCancelled != nil }
        XCTAssertEqual(isLoadCancelled, false)
    }

    /// Кейс: пока ждётся отправитель, переписку открыли.
    /// Ожидание: уведомления нет.
    func test_received_conversationOpenedWhileWaiting_showsNothing() async {
        userCache.users = [:]
        holdsLoads = true
        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))
        await yieldUntil { loadGates.count == 1 }

        navigator.openConversationIds = [1]
        loadGates[0].open()

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: первое сообщение ждёт отправителя, приходит второе — от загруженного отправителя; затем первый
    /// отправитель загрузился.
    /// Ожидание: показано только второе.
    func test_received_newerMessage_replacesPreparation() async {
        userCache.users = [2: .loaded(anna)]
        let unknownSender = 3
        holdsLoads = true
        await queue.send(.received(.make(id: 7, conversationId: 2, senderId: unknownSender)))
        await yieldUntil { loadGates.count == 1 }

        await queue.send(.received(.make(id: 8, conversationId: 1, senderId: 2)))
        await yieldUntil { notifications.shownMessages.count == 1 }
        loadGates[0].open()

        await yieldTimes()
        XCTAssertEqual(notifications.shownMessages.map(\.messageId), [8])
    }

    /// Кейс: пока ждётся отправитель, начался выход из аккаунта.
    /// Ожидание: уведомления нет.
    func test_authServiceWillLogout_cancelsPreparation() async {
        userCache.users = [:]
        holdsLoads = true
        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))
        await yieldUntil { loadGates.count == 1 }

        await sut.authServiceWillLogout()
        loadGates[0].open()

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: нажатие на показанное уведомление.
    /// Ожидание: навигатор открывает переписку сообщения.
    func test_onTap_opensConversation() async {
        await queue.send(.received(.make(id: 7, conversationId: 2, senderId: 2)))
        await yieldUntil { notifications.shown.count == 1 }

        notifications.shown.first?.onTap?()

        XCTAssertEqual(navigator.openRequests, [2])
    }

    /// Кейс: показано уведомление о переписке 1; открылась переписка 2, затем переписка 1.
    /// Ожидание: открытие другой переписки уведомление не трогает, открытие переписки 1 его скрывает.
    func test_conversationDidOpen_dismissesItsNotification() async {
        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))
        await yieldUntil { notifications.current != nil }

        sut.conversationDidOpen(2)
        XCTAssertNotNil(notifications.current)

        sut.conversationDidOpen(1)
        XCTAssertNil(notifications.current)
    }

    /// Кейс: показана ошибка; открылась переписка.
    /// Ожидание: ошибка остаётся.
    func test_conversationDidOpen_keepsErrorNotification() {
        notifications.showError("Ошибка")

        sut.conversationDidOpen(1)

        XCTAssertNotNil(notifications.current)
    }

    /// Кейс: пока ждётся отправитель, переписку открыли (`conversationDidOpen`), затем отправитель загрузился.
    /// Ожидание: подготовка отменена, уведомления нет.
    func test_conversationDidOpen_cancelsPreparation() async {
        userCache.users = [:]
        holdsLoads = true
        await queue.send(.received(.make(id: 7, conversationId: 1, senderId: 2)))
        await yieldUntil { loadGates.count == 1 }

        sut.conversationDidOpen(1)
        loadGates[0].open()

        await yieldTimes()
        XCTAssertTrue(notifications.shown.isEmpty)
    }

    /// Кейс: `start()` вызван повторно (вход после выхода).
    /// Ожидание: подписка на очередь одна.
    func test_start_twice_subscribesOnce() {
        sut.start()

        XCTAssertEqual(queue.subscriberCount, 1)
    }
}
