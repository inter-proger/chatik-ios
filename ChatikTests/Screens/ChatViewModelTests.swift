//
//  ChatViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var list: MessagesListServiceMock!
    private var messageSendQueue: MessageSendQueueMock!
    private var sessionService: SessionService!
    private var draftService: MessageDraftServiceMock!
    private var userCache: UserCacheServiceMock!
    private var localizationService: LocalizationService!
    private var timeChanges: SignificantTimeChangeServiceMock!
    private var sleeper: ThrottleSleeper!
    private var observation: Task<Void, Never>?
    /// Текущее время для тестов заголовков дней.
    private var currentTime = ServerTime.stub.date

    override func setUp() async throws {
        try await super.setUp()
        list = MessagesListServiceMock()
        messageSendQueue = MessageSendQueueMock()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        draftService = MessageDraftServiceMock()
        userCache = UserCacheServiceMock()
        localizationService = LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru)
        timeChanges = SignificantTimeChangeServiceMock()
        sleeper = ThrottleSleeper()
    }

    override func tearDown() async throws {
        observation?.cancel()
        sleeper.releaseAll()
        await observation?.value
        observation = nil
        try await super.tearDown()
    }

    // MARK: - Лента

    /// Кейс: экран открыт, затем закрыт (задача наблюдения отменена).
    /// Ожидание: лента запущена при открытии и остановлена при закрытии.
    func test_observeMessages_startsAndStopsList() async {
        let sut = makeSUT()
        await startObserving(sut)
        XCTAssertEqual(list.startCallCount, 1)

        observation?.cancel()
        sleeper.releaseAll()
        await observation?.value
        observation = nil

        XCTAssertEqual(list.stopCallCount, 1)
    }

    /// Кейс: лента обновилась; за интервал после этого пришли ещё два снимка; затем интервал истёк.
    /// Ожидание: пока интервал не истёк, сообщения прежние; после — последняя версия; пауза — 0,5 с.
    func test_snapshots_withinInterval_areCoalesced() async {
        let sut = makeSUT()
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 1)], isUrgent: true))
        await waitUntil { sut.messages.count == 1 }
        await yieldUntil { [unowned self] in sleeper.isWaiting }

        list.publish(.make(messages: [.make(id: 2), .make(id: 1)]))
        list.publish(.make(messages: [.make(id: 3), .make(id: 2), .make(id: 1)]))
        await yieldTimes()
        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(1))
        sleeper.releaseAll()

        await waitUntil { sut.messages.count == 3 }
        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(3, 2, 1))
        XCTAssertEqual(sleeper.requested.first, ChatViewModel.messagesUpdateInterval)
    }

    /// Кейс: идёт пауза между обновлениями; пришёл срочный снимок (своё отправленное сообщение).
    /// Ожидание: он показан сразу, не дожидаясь конца паузы.
    func test_urgentSnapshot_interruptsInterval() async {
        let sut = makeSUT()
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 1)], isUrgent: true))
        await waitUntil { sut.messages.count == 1 }
        await yieldUntil { [unowned self] in sleeper.isWaiting }

        list.publish(.make(messages: [.make(id: 2), .make(id: 1)], isUrgent: true))

        await waitUntil { sut.messages.count == 2 }
    }

    /// Кейс: идёт пауза между обновлениями; нажата «Отправить».
    /// Ожидание: неотправленное сообщение показано сразу.
    func test_didTapSend_showsOutgoingImmediately() async {
        let sut = makeSUT()
        await startObserving(sut)
        await yieldUntil { [unowned self] in sleeper.isWaiting }
        sut.messageText = "Привет"

        sut.didTapSend()
        messageSendQueue.outgoingMessages = [.stub(clientId: "c1")]

        await waitUntil { sut.messages.map(\.id.clientId) == ["c1"] }
    }

    /// Кейс: идёт синхронизация, кэша нет; затем синхронизация закончилась пустой лентой.
    /// Ожидание: сначала индикатор и прелоадер — сразу, без паузы; затем, когда пустое окно собрано, — экран
    /// «сообщений нет».
    func test_syncing_showsIndicatorThenEmpty() async {
        let sut = makeSUT()
        await startObserving(sut)
        await yieldUntil { [unowned self] in sleeper.isWaiting }

        list.publish(.make(isSyncing: true))
        await yieldUntil { sut.isSyncing }
        XCTAssertTrue(sut.isShowingLoader)
        XCTAssertFalse(sut.isEmpty)
        list.publish(.make(isSyncing: false))
        sleeper.releaseAll()

        await yieldUntil { sut.isEmpty }
        XCTAssertFalse(sut.isShowingLoader)
    }

    /// Кейс: кэш ещё читается — пустой срочный снимок без синхронизации, окно не прочитано; затем окно прочитано.
    /// Ожидание: пока кэш читается — прелоадер, а не «сообщений нет»; после прочтения — «сообщений нет».
    func test_windowNotLoaded_showsLoaderInsteadOfEmpty() async {
        let sut = makeSUT()
        await startObserving(sut)

        list.publish(.make(isLoaded: false, isUrgent: true))
        await yieldUntil { [unowned self] in sleeper.isWaiting }
        XCTAssertTrue(sut.isShowingLoader)
        XCTAssertFalse(sut.isEmpty)
        list.publish(.make(isUrgent: true))

        await yieldUntil { sut.isEmpty }
        XCTAssertFalse(sut.isShowingLoader)
    }

    /// Кейс: экран появился снова, пока прежнее наблюдение ещё завершается (новый `.task` запущен до конца старого).
    /// Ожидание: лента не перезапускается и не останавливается, пока жив новый наблюдатель, и новые снимки
    /// попадают в ленту; после его отмены лента остановлена один раз.
    func test_observeMessages_overlappingObservations_keepListRunning() async {
        let sut = makeSUT()
        await startObserving(sut)
        await yieldUntil { [unowned self] in sleeper.requested.count == 1 }
        let second = Task { await sut.observeMessages() }
        await yieldUntil { [unowned self] in sleeper.requested.count == 2 }

        observation?.cancel()
        sleeper.releaseAll()
        await observation?.value
        observation = second
        list.publish(.make(messages: [.make(id: 1)], isUrgent: true))

        await waitUntil { sut.messages.count == 1 }
        XCTAssertEqual(list.startCallCount, 1)
        XCTAssertEqual(list.stopCallCount, 0)
        second.cancel()
        sleeper.releaseAll()
        await second.value
        XCTAssertEqual(list.stopCallCount, 1)
    }

    /// Кейс: в снимке ошибка синхронизации.
    /// Ожидание: показано сообщение об ошибке.
    func test_snapshotFailure_showsError() async {
        let sut = makeSUT()
        await startObserving(sut)

        list.publish(.make(failure: NetworkError.transport(URLError(.notConnectedToInternet))))

        await yieldUntil { sut.errorMessage != nil }
    }

    /// Кейс: pull-to-refresh.
    /// Ожидание: запущена синхронизация ленты.
    func test_refresh_synchronizesList() async {
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertEqual(list.synchronizeCallCount, 1)
    }

    /// Кейс: показано одно из самых старых сообщений, есть более старые; затем — когда более старых нет.
    /// Ожидание: подгрузка запрошена только в первом случае.
    func test_prefetchOlder_requestsOnlyWhenOlderExist() async {
        let sut = makeSUT()
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 2), .make(id: 1)], hasOlder: true, isUrgent: true))
        await waitUntil { sut.messages.count == 2 }

        sut.prefetchOlderIfNeeded(currentMessage: sut.messages[1])
        await yieldUntil { [unowned self] in list.loadOlderCallCount == 1 }
        list.publish(.make(messages: [.make(id: 2), .make(id: 1)], hasOlder: false, isUrgent: true))
        await yieldUntil { !sut.hasOlder }
        sut.prefetchOlderIfNeeded(currentMessage: sut.messages[1])
        await yieldTimes()

        XCTAssertEqual(list.loadOlderCallCount, 1)
    }

    // MARK: - Отображение

    /// Кейс: в переписке сообщения текущего пользователя и собеседника.
    /// Ожидание: сообщения текущего пользователя исходящие, собеседника — входящие.
    func test_messages_marksOutgoingByCurrentUser() async {
        let sut = makeSUT()
        await startObserving(sut)

        list.publish(.make(messages: [.make(id: 2, senderId: 2), .make(id: 1, senderId: 1)], isUrgent: true))

        await waitUntil { sut.messages.map(\.isOutgoing) == [false, true] }
    }

    /// Кейс: групповая переписка, сообщения идут сериями: два от собеседника, перед ними два от текущего пользователя.
    /// Ожидание: имя (и аватар) есть только у первого по времени сообщения каждой серии — у своих из сессии,
    /// у чужих из кэша; у кэша запрошен только собеседник.
    func test_messages_series_showsSenderOnFirstMessageOnly() async {
        let sut = makeSUT(conversation: .groupStub)
        userCache.users[3] = .loaded(User(userId: 3, login: "olga", name: "Olga", avatar: nil))
        let page = [
            Message.make(id: 4, senderId: 3),
            Message.make(id: 3, senderId: 3),
            Message.make(id: 2, senderId: 1),
            Message.make(id: 1, senderId: 1),
        ]
        await startObserving(sut)

        list.publish(.make(messages: page, isUrgent: true))

        await waitUntil { sut.messages.count == 4 }
        XCTAssertEqual(sut.messages.map(\.sender?.name), [nil, "Olga", nil, "Ivan"])
        XCTAssertEqual(userCache.loadRequests, [[3]])
    }

    /// Кейс: личная переписка, сообщения собеседника и текущего пользователя чередуются.
    /// Ожидание: у каждого сообщения есть отправитель — в личной переписке аватары и имена тоже показываются.
    func test_messages_single_showsSenders() async {
        let sut = makeSUT()
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil))
        await startObserving(sut)

        list.publish(.make(messages: [.make(id: 2, senderId: 2), .make(id: 1, senderId: 1)], isUrgent: true))

        await waitUntil { sut.messages.map(\.sender?.name) == ["Petr", "Ivan"] }
    }

    // MARK: - Заголовок

    /// Кейс: групповая переписка с названием.
    /// Ожидание: заголовок — название группы, без заглушки.
    func test_title_group_usesName() {
        let sut = makeSUT(conversation: .groupStub)

        XCTAssertEqual(sut.title, Conversation.groupStub.name)
        XCTAssertFalse(sut.isTitlePlaceholder)
    }

    /// Кейс: личная переписка, собеседник есть в кэше.
    /// Ожидание: заголовок — имя собеседника.
    func test_title_single_usesOpponentName() {
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil))
        let sut = makeSUT()

        XCTAssertEqual(sut.title, "Petr")
        XCTAssertFalse(sut.isTitlePlaceholder)
    }

    /// Кейс: личная переписка, собеседник ещё не загружен.
    /// Ожидание: заголовок показывается заглушкой.
    func test_title_single_opponentPending_isPlaceholder() {
        let sut = makeSUT()

        XCTAssertEqual(sut.title, ChatStrings.userLoading)
        XCTAssertTrue(sut.isTitlePlaceholder)
    }

    // MARK: - Ввод

    /// Кейс: в поле ввода пусто или только пробелы и переводы строк.
    /// Ожидание: кнопка отправки неактивна, подсказки нет.
    func test_isSendEnabled_blankText_isDisabled() {
        let sut = makeSUT()
        let texts = [
            "",
            "   ",
            "\n\t",
        ]

        for text in texts {
            sut.messageText = text
            XCTAssertFalse(sut.isSendEnabled, text)
            XCTAssertNil(sut.inputHint, text)
        }
    }

    /// Кейс: в поле ввода текст длиннее лимита сервера.
    /// Ожидание: кнопка отправки неактивна, показана подсказка о лимите.
    func test_isSendEnabled_tooLongText_isDisabledWithHint() {
        let sut = makeSUT()

        sut.messageText = String(repeating: "a", count: MessageTextValidator.maxLength + 1)

        XCTAssertFalse(sut.isSendEnabled)
        XCTAssertEqual(sut.inputHint, ChatStrings.inputTooLong(maxLength: MessageTextValidator.maxLength))
    }

    /// Кейс: в поле ввода обычный текст.
    /// Ожидание: кнопка отправки активна.
    func test_isSendEnabled_validText_isEnabled() {
        let sut = makeSUT()

        sut.messageText = "Привет"

        XCTAssertTrue(sut.isSendEnabled)
    }

    // MARK: - Отправка

    /// Кейс: нажата «Отправить».
    /// Ожидание: текст из поля поставлен в очередь в открытую переписку, поле сразу очищено.
    func test_didTapSend_enqueuesAndClearsInput() {
        let sut = makeSUT()
        sut.messageText = "Привет"

        sut.didTapSend()

        XCTAssertEqual(messageSendQueue.enqueued.map(\.text), ["Привет"])
        XCTAssertEqual(messageSendQueue.enqueued.map(\.conversationId), [Conversation.singleStub.id])
        XCTAssertEqual(sut.messageText, "")
    }

    /// Кейс: нажата «Отправить» с пустым полем.
    /// Ожидание: в очередь ничего не поставлено.
    func test_didTapSend_blankText_isIgnored() {
        let sut = makeSUT()
        sut.messageText = "  "

        sut.didTapSend()

        XCTAssertTrue(messageSendQueue.enqueued.isEmpty)
    }

    /// Кейс: в очереди неотправленные сообщения этой и другой переписки; на экране есть сообщение с сервера.
    /// Ожидание: показаны только сообщения этой переписки — в самом низу ленты, под сообщениями с сервера,
    /// исходящие и в своих статусах.
    func test_messages_showsOutgoingOfThisConversationAtBottom() async {
        let sut = makeSUT()
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 5, senderId: 2)], isUrgent: true))
        await waitUntil { sut.messages.count == 1 }

        messageSendQueue.outgoingMessages = [
            .stub(clientId: "a", status: .failed),
            .stub(clientId: "other", conversationId: 99),
            .stub(clientId: "b", status: .sending),
        ]
        // Мок очереди не наблюдаемый: об изменении сообщает следующий снимок.
        list.publish(.make(messages: [.make(id: 5, senderId: 2)], isUrgent: true))

        await waitUntil { sut.messages.count == 3 }
        XCTAssertEqual(sut.messages.map(\.id.clientId), ["b", "a", "client-5"])
        XCTAssertEqual(sut.messages.map(\.deliveryState), [.sending, .failed, .delivered])
        XCTAssertEqual(sut.messages.map(\.isOutgoing), [true, true, false])
        XCTAssertFalse(sut.isEmpty)
    }

    /// Кейс: лента уже содержит серверную версию сообщения, а очередь ещё держит его неотправленную копию.
    /// Ожидание: в ленте одно сообщение с этим `clientId` — серверная версия.
    func test_messages_sentAndStillInQueue_showsOnce() async {
        let sut = makeSUT()
        messageSendQueue.outgoingMessages = [.stub(clientId: "c1")]
        await startObserving(sut)

        list.publish(.make(messages: [.make(id: 2, clientId: "c1")], isUrgent: true))

        await waitUntil { sut.messages.map(\.deliveryState) == [.delivered] }
        XCTAssertEqual(sut.messages.map(\.id.clientId), ["c1"])
        XCTAssertNotNil(sut.messages.first?.time)
    }

    /// Кейс: тап по доставленному и по неотправленному сообщению.
    /// Ожидание: выбор действий показывается только для неотправленного.
    func test_didTapMessage_showsActionsForFailedOnly() async {
        let sut = makeSUT()
        messageSendQueue.outgoingMessages = [.stub(clientId: "a", status: .failed)]
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 1)], isUrgent: true))
        await waitUntil { sut.messages.count == 2 }

        sut.didTapMessage(sut.messages[1])
        XCTAssertNil(sut.failedMessageActionsClientId)
        sut.didTapMessage(sut.messages[0])

        XCTAssertEqual(sut.failedMessageActionsClientId, "a")
    }

    /// Кейс: в выборе действий нажаты «Повторить отправку» и «Удалить сообщение».
    /// Ожидание: действия переданы очереди с `clientId` сообщения.
    func test_retryAndDelete_forwardToQueue() {
        let sut = makeSUT()

        sut.retrySending(clientId: "a")
        sut.deleteOutgoing(clientId: "b")

        XCTAssertEqual(messageSendQueue.retriedClientIds, ["a"])
        XCTAssertEqual(messageSendQueue.deletedClientIds, ["b"])
    }

    // MARK: - Черновик

    /// Кейс: у переписки есть черновик; экран открыт.
    /// Ожидание: черновик подставлен в поле ввода, при этом в сервис черновиков ничего не записано.
    func test_init_fillsInputFromDraftWithoutWriting() {
        draftService.drafts = [Conversation.singleStub.id: "Привет"]

        let sut = makeSUT()

        XCTAssertEqual(sut.messageText, "Привет")
        XCTAssertTrue(draftService.updates.isEmpty)
        XCTAssertTrue(draftService.saves.isEmpty)
        XCTAssertTrue(draftService.removals.isEmpty)
    }

    /// Кейс: пользователь меняет текст в поле ввода.
    /// Ожидание: каждое изменение передаётся сервису как черновик пользователя сессии в открытой переписке.
    func test_messageText_change_updatesDraft() {
        let sut = makeSUT()

        sut.messageText = "П"
        sut.messageText = "Привет"

        XCTAssertEqual(draftService.updates, [
            MessageDraftServiceMock.Call(text: "П", conversationId: Conversation.singleStub.id, userId: 1),
            MessageDraftServiceMock.Call(text: "Привет", conversationId: Conversation.singleStub.id, userId: 1),
        ])
        XCTAssertTrue(draftService.saves.isEmpty)
    }

    /// Кейс: в поле текст; экран сохраняет черновик (уход с экрана или приложения в фон).
    /// Ожидание: сервису передан текст поля, переписка и пользователь сессии.
    func test_saveDraft_passesTextAndUser() {
        let sut = makeSUT()
        sut.messageText = "Привет"

        sut.saveDraft()

        XCTAssertEqual(draftService.saves, [MessageDraftServiceMock.Call(text: "Привет", conversationId: Conversation.singleStub.id, userId: 1)])
    }

    /// Кейс: экран открыт; сессия завершилась (истекла) раньше, чем экран ушёл; экран сохраняет черновик.
    /// Ожидание: черновик сохраняется пользователю, открывшему экран, а не текущей (пустой) сессии.
    func test_saveDraft_afterSessionEnded_usesUserWhoOpenedScreen() async {
        let sut = makeSUT()
        sut.messageText = "Набрано до выхода"
        await sessionService.end()

        sut.saveDraft()

        XCTAssertEqual(draftService.saves.map(\.userId), [1])
    }

    /// Кейс: сессии нет; экран открыт, текст набран и сохранён.
    /// Ожидание: черновики не меняются и не сохраняются.
    func test_draft_withoutSession_isIgnored() async {
        await sessionService.end()
        let sut = makeSUT()

        sut.messageText = "Текст"
        sut.saveDraft()

        XCTAssertTrue(draftService.updates.isEmpty)
        XCTAssertTrue(draftService.saves.isEmpty)
    }

    /// Кейс: в поле текст; нажата «Отправить».
    /// Ожидание: черновик удалён сразу, не дожидаясь ухода с экрана.
    func test_didTapSend_removesDraft() {
        let sut = makeSUT()
        sut.messageText = "Привет"

        sut.didTapSend()

        XCTAssertEqual(draftService.removals.map(\.conversationId), [Conversation.singleStub.id])
        XCTAssertEqual(draftService.removals.map(\.userId), [1])
    }

    // MARK: - Секции по дням

    /// Кейс: сообщения сегодняшнего, вчерашнего и позавчерашнего дня.
    /// Ожидание: три секции от новых к старым, у каждой заголовок своего дня: «Сегодня, …», «Вчера, …», день недели.
    func test_sections_splitByDay_newestFirstWithTitles() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        let page = [
            Message.make(id: 3, createdAt: day(0)),
            Message.make(id: 2, createdAt: day(-1)),
            Message.make(id: 1, createdAt: day(-2)),
        ]
        await startObserving(sut)

        list.publish(.make(messages: page, isUrgent: true))

        await waitUntil { sut.sections.count == 3 }
        let formatter = RussianMessageDateHeaderFormatter(calendar: .stub())
        XCTAssertEqual(sut.sections.map(\.title), page.map { formatter.string(from: $0.createdAt.date, now: currentTime) })
        XCTAssertTrue(sut.sections[0].title.hasPrefix("Сегодня, "), sut.sections[0].title)
        XCTAssertTrue(sut.sections[1].title.hasPrefix("Вчера, "), sut.sections[1].title)
        XCTAssertEqual(sut.sections.map { $0.messages.map(\.id.clientId) }, [clientIds(3), clientIds(2), clientIds(1)])
    }

    /// Кейс: два сообщения собеседника подряд, но в разные дни.
    /// Ожидание: серия прерывается на границе дня — у обоих сообщений есть отправитель.
    func test_sections_senderSeriesBreaksAtDayBoundary() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil))
        await startObserving(sut)

        list.publish(.make(messages: [.make(id: 2, senderId: 2, createdAt: day(0)), .make(id: 1, senderId: 2, createdAt: day(-1))], isUrgent: true))

        await waitUntil { sut.sections.count == 2 }
        XCTAssertEqual(sut.messages.map(\.sender?.name), ["Petr", "Petr"])
    }

    /// Кейс: вчерашнее неотправленное сообщение внизу ленты, под сегодняшним и вчерашним с сервера.
    /// Ожидание: оно остаётся внизу — во второй секции того же дня, с номером серии 1; секция с сервера — с номером 0.
    func test_sections_yesterdayFailedUnderToday_isSecondSectionOfSameDay() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        messageSendQueue.outgoingMessages = [.stub(clientId: "a", createdAt: day(-1).date, status: .failed)]
        await startObserving(sut)

        list.publish(.make(messages: [.make(id: 2, createdAt: day(0)), .make(id: 1, createdAt: day(-1))], isUrgent: true))

        await waitUntil { sut.sections.count == 3 }
        XCTAssertEqual(sut.sections.map(\.id.occurrence), [1, 0, 0])
        XCTAssertEqual(sut.sections[0].id.day, sut.sections[2].id.day)
        XCTAssertEqual(sut.sections[0].messages.map(\.id.clientId), ["a"])
    }

    /// Кейс: в ленте есть вчерашнее неотправленное под сегодняшними; подгрузились сообщения позавчерашнего дня.
    /// Ожидание: `id` уже показанных секций не изменились, новая секция добавлена в конец.
    func test_sections_loadOlder_keepsShownSectionIDs() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        messageSendQueue.outgoingMessages = [.stub(clientId: "a", createdAt: day(-1).date, status: .failed)]
        let page = [Message.make(id: 2, createdAt: day(0)), Message.make(id: 1, createdAt: day(-1))]
        await startObserving(sut)
        list.publish(.make(messages: page, isUrgent: true))
        await waitUntil { sut.sections.count == 3 }
        let shownIDs = sut.sections.map(\.id)

        list.publish(.make(messages: page + [.make(id: 0, createdAt: day(-2))], isUrgent: true))

        await waitUntil { sut.sections.count == 4 }
        XCTAssertEqual(Array(sut.sections.map(\.id).prefix(3)), shownIDs)
    }

    /// Кейс: на экране сегодняшнее сообщение, идёт пауза между обновлениями; наступила полночь.
    /// Ожидание: событие смены времени пересобирает ленту сразу — заголовок становится «Вчера, …».
    func test_timeChange_rebuildsTitlesImmediately() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 1, createdAt: day(0))], isUrgent: true))
        await waitUntil { sut.sections.first?.title.hasPrefix("Сегодня, ") == true }
        await yieldUntil { [unowned self] in sleeper.isWaiting && timeChanges.subscriberCount == 1 }

        currentTime = currentTime.addingTimeInterval(86_400)
        timeChanges.send()

        await waitUntil { sut.sections.first?.title.hasPrefix("Вчера, ") == true }
    }

    /// Кейс: экран открыт, затем закрыт.
    /// Ожидание: подписка на смену времени есть, пока экран открыт, и снимается при закрытии.
    func test_timeChange_afterLeavingScreen_unsubscribes() async {
        let sut = makeSUT()
        await startObserving(sut)
        await yieldUntil { [unowned self] in timeChanges.subscriberCount == 1 }

        observation?.cancel()
        sleeper.releaseAll()
        await observation?.value

        await waitUntil { [unowned self] in timeChanges.subscriberCount == 0 }
    }

    /// Кейс: на экране сегодняшнее сообщение; язык приложения сменился на английский.
    /// Ожидание: заголовки дней переведены — «Today, …».
    func test_languageChange_translatesTitles() async {
        let sut = makeSUT(now: { [unowned self] in currentTime })
        await startObserving(sut)
        list.publish(.make(messages: [.make(id: 1, createdAt: day(0))], isUrgent: true))
        await waitUntil { sut.sections.first?.title.hasPrefix("Сегодня, ") == true }

        await localizationService.setLanguage(.en)
        sleeper.releaseAll()

        await waitUntil { sut.sections.first?.title.hasPrefix("Today, ") == true }
    }

    // MARK: - Helpers

    /// Время сообщения, сдвинутое от `ServerTime.stub` на целое число суток.
    /// - Parameter offset: сдвиг в сутках; отрицательный — в прошлое.
    private func day(_ offset: Int) -> ServerTime {
        .stub(Int64(offset) * 86_400_000)
    }

    /// Создаёт ViewModel над моками этого теста.
    /// - Parameters:
    ///   - conversation: открытая переписка; по умолчанию — личная с собеседником 2.
    ///   - now: текущее время; по умолчанию — часы устройства.
    private func makeSUT(conversation: Conversation = .singleStub, now: @escaping () -> Date = { Date() }) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            messagesList: list,
            messageSendQueue: messageSendQueue,
            sessionService: sessionService,
            draftService: draftService,
            userCache: userCache,
            localizationService: localizationService,
            messageTextValidator: MessageTextValidator(),
            dateHeaderFormatterProvider: MessageDateHeaderFormatterProvider.default,
            timeChangeService: timeChanges,
            now: now,
            calendar: { .stub() },
            sleep: { [sleeper] in try await sleeper!.sleep($0) }
        )
    }

    /// Запускает наблюдение за лентой, как `.task` экрана, и ждёт подписки на снимки.
    /// - Parameter sut: ViewModel.
    private func startObserving(_ sut: ChatViewModel) async {
        observation = Task { await sut.observeMessages() }
        await yieldUntil { [unowned self] in list.subscriberCount == 1 && list.startCallCount == 1 }
    }

    /// `clientId` сообщений из `Message.make` с заданными `messageId`.
    /// - Parameter ids: `messageId` сообщений в порядке ленты.
    private func clientIds(_ ids: Int...) -> [String] {
        ids.map { "client-\($0)" }
    }
}

private extension ChatViewModel {
    /// Сообщения всех секций в плоском порядке ленты, сначала самые новые.
    var messages: [MessageDisplayModel] {
        sections.flatMap(\.messages)
    }
}

/// Пауза между обновлениями ленты: длится до `releaseAll()` или отмены.
@MainActor
private final class ThrottleSleeper {
    /// Запрошенные паузы по порядку.
    private(set) var requested: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    /// `true`, пока идёт пауза.
    var isWaiting: Bool {
        !continuations.isEmpty
    }

    /// Пауза до `releaseAll()`; отмена задачи её прерывает.
    /// - Parameter duration: длительность паузы.
    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuations.append($0) }
        } onCancel: {
            Task { @MainActor in self.releaseAll() }
        }
        try Task.checkCancellation()
    }

    /// Завершает все идущие паузы.
    func releaseAll() {
        let continuations = continuations
        self.continuations = []
        continuations.forEach { $0.resume() }
    }
}
