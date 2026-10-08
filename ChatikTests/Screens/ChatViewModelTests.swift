//
//  ChatViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var messageService: MessageServiceMock!
    private var messageStorage: MessageStorageServiceMock!
    private var messageSendQueue: MessageSendQueueMock!
    private var sessionService: SessionService!
    private var userCache: UserCacheServiceMock!
    private var realtimeService: RealtimeServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        messageService = MessageServiceMock()
        messageStorage = MessageStorageServiceMock()
        messageSendQueue = MessageSendQueueMock()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        userCache = UserCacheServiceMock()
        realtimeService = RealtimeServiceMock()
    }

    // MARK: - Список

    /// Кейс: сервер вернул страницу сообщений.
    /// Ожидание: сообщения показаны в порядке ответа (сначала новые), запрос ушёл за открытую переписку
    /// с самого нового блока, флаг загрузки снят.
    func test_loadFirstPage_success_showsMessages() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(2, 1))
        XCTAssertEqual(messageService.pageRequests.map(\.conversationId), [Conversation.singleStub.id])
        XCTAssertEqual(messageService.pageRequests.map(\.blockId), [nil])
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: сервер вернул пустую страницу.
    /// Ожидание: экран показывает сообщение об отсутствии сообщений.
    func test_loadFirstPage_emptyPage_isEmpty() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertTrue(sut.isEmpty)
    }

    /// Кейс: показано одно из самых старых сообщений первой страницы, у сервера есть более старые.
    /// Ожидание: следующая страница запрошена с курсором `nextBlockId` и дописана в конец списка.
    func test_prefetchNextPage_usesNextBlockIdAndAppends() async throws {
        let sut = makeSUT()
        let firstPage = (3...14).reversed().map { Message.make(id: $0) }
        messageService.stubbedPages = [
            .success(MessagesPage(messages: firstPage, nextBlockId: 5, hasNext: true)),
            .success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false)),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentMessage: try XCTUnwrap(sut.messages.last))
        await yieldUntil { [unowned self] in messageService.pageRequests.count == 2 && !sut.isLoadingNextPage }

        XCTAssertEqual(messageService.pageRequests.last?.blockId, 5)
        XCTAssertEqual(sut.messages.map(\.id.clientId), (1...14).reversed().map { "client-\($0)" })
    }

    /// Кейс: транспортная ошибка при загрузке первой страницы.
    /// Ожидание: показано сообщение об отсутствии соединения.
    func test_loadFirstPage_transportError_showsError() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    // MARK: - Обновление

    /// Кейс: лента показана, пользователь тянет её для обновления (pull-to-refresh), пришли новые сообщения.
    /// Ожидание: лента заменена новой первой страницей, запрос ушёл с самого нового блока, БД повторно не читается.
    func test_loadFirstPage_again_replacesMessages() async {
        let sut = makeSUT()
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false)),
            .success(MessagesPage(messages: [.make(id: 3), .make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false)),
        ]
        await sut.loadFirstPage()

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(3, 2, 1))
        XCTAssertEqual(messageService.pageRequests.map(\.blockId), [nil, nil])
        XCTAssertEqual(messageStorage.fetchLatestRequests.count, 1)
    }

    /// Кейс: обновление не удалось — нет сети.
    /// Ожидание: прежние сообщения остаются на экране, показано сообщение об ошибке.
    func test_loadFirstPage_againTransportError_keepsMessages() async {
        let sut = makeSUT()
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false)),
            .failure(NetworkError.transport(URLError(.notConnectedToInternet))),
        ]
        await sut.loadFirstPage()

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(1))
        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    /// Кейс: SwiftUI отменил задачу, из которой запущено обновление, пока шёл запрос.
    /// Ожидание: загрузка не прерывается — сообщения показаны, ошибки нет.
    func test_loadFirstPage_callerCancelled_completesLoading() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        messageService.onFetch = { await gate.wait() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        load.cancel()
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(1))
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Локальная БД

    /// Кейс: сервер вернул страницу сообщений.
    /// Ожидание: страница сохранена в локальную БД.
    func test_loadFirstPage_savesPageToStorage() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(messageStorage.savedMessages.map(\.id), [2, 1])
    }

    /// Кейс: в БД есть сообщения переписки, экран открывается.
    /// Ожидание: из БД читаются последние сообщения этой переписки в пределах лимита; до ответа сервера показаны
    /// они, после — заменены ответом.
    func test_loadFirstPage_withCache_showsCacheThenNetwork() async {
        let sut = makeSUT()
        let gate = Gate()
        messageStorage.stubbedMessages = .success([.make(id: 1)])
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false))]
        messageService.onFetch = { await gate.wait() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        await yieldUntil { sut.messages.map(\.id.clientId) == clientIds(1) }
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(2, 1))
        XCTAssertEqual(messageStorage.fetchLatestRequests.map(\.conversationId), [Conversation.singleStub.id])
        XCTAssertEqual(messageStorage.fetchLatestRequests.map(\.limit), [ChatViewModel.cachedMessagesLimit])
    }

    /// Кейс: в БД есть сообщения переписки, сети нет.
    /// Ожидание: сообщения из БД остаются на экране, показано сообщение об ошибке.
    func test_loadFirstPage_withCache_transportError_keepsCachedMessages() async {
        let sut = makeSUT()
        messageStorage.stubbedMessages = .success([.make(id: 2), .make(id: 1)])
        messageService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(2, 1))
        XCTAssertFalse(sut.isEmpty)
        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    /// Кейс: БД не прочиталась и не записала страницу.
    /// Ожидание: ошибки БД пользователю не показываются, страница с сервера на экране.
    func test_loadFirstPage_storageErrors_showsNetworkPageSilently() async {
        let sut = makeSUT()
        messageStorage.stubbedMessages = .failure(CocoaError(.fileReadUnknown))
        messageStorage.stubbedSaveError = CocoaError(.fileReadUnknown)
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(1))
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Отображение

    /// Кейс: в переписке сообщения текущего пользователя и собеседника.
    /// Ожидание: сообщения текущего пользователя исходящие, собеседника — входящие.
    func test_messages_marksOutgoingByCurrentUser() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2, senderId: 2), .make(id: 1, senderId: 1)], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.isOutgoing), [false, true])
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
        messageService.stubbedPages = [.success(MessagesPage(messages: page, nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()
        await yieldUntil { [unowned self] in !userCache.loadRequests.isEmpty }

        XCTAssertEqual(sut.messages.map(\.sender?.name), [nil, "Olga", nil, "Ivan"])
        XCTAssertEqual(userCache.loadRequests, [[3]])
    }

    /// Кейс: личная переписка, сообщения собеседника и текущего пользователя чередуются.
    /// Ожидание: у каждого сообщения есть отправитель — в личной переписке аватары и имена тоже показываются.
    func test_messages_single_showsSenders() async {
        let sut = makeSUT()
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil))
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 2, senderId: 2), .make(id: 1, senderId: 1)], nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.sender?.name), ["Petr", "Ivan"])
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
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 5, senderId: 2)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        messageSendQueue.outgoingMessages = [
            .stub(clientId: "a", status: .failed),
            .stub(clientId: "other", conversationId: 99),
            .stub(clientId: "b", status: .sending),
        ]

        XCTAssertEqual(sut.messages.map(\.id.clientId), ["b", "a", "client-5"])
        XCTAssertEqual(sut.messages.map(\.deliveryState), [.sending, .failed, .delivered])
        XCTAssertEqual(sut.messages.map(\.isOutgoing), [true, true, false])
        XCTAssertFalse(sut.isEmpty)
    }

    /// Кейс: очередь опубликовала сообщение, созданное сервером, — этой переписки и другой.
    /// Ожидание: сообщение этой переписки встало в ленту, чужое — нет.
    func test_observeSentMessages_appliesThisConversationOnly() async {
        let sut = makeSUT()
        let observation = Task { await sut.observeSentMessages() }
        await yieldUntil { [unowned self] in messageSendQueue.subscriberCount == 1 }

        messageSendQueue.publishSent(.make(id: 3, conversationId: 99))
        messageSendQueue.publishSent(.make(id: 2, clientId: "c1"))

        await yieldUntil { sut.messages.map(\.id.clientId) == ["c1"] }
        observation.cancel()
        await observation.value
    }

    /// Кейс: очередь опубликовала сообщение, созданное сервером, но ещё держит его неотправленную копию.
    /// Ожидание: в ленте одно сообщение с этим `clientId` — серверная версия.
    func test_messages_sentAndStillInQueue_showsOnce() async {
        let sut = makeSUT()
        let observation = Task { await sut.observeSentMessages() }
        await yieldUntil { [unowned self] in messageSendQueue.subscriberCount == 1 }
        messageSendQueue.outgoingMessages = [.stub(clientId: "c1")]

        messageSendQueue.publishSent(.make(id: 2, clientId: "c1"))

        await yieldUntil { sut.messages.map(\.deliveryState) == [.delivered] }
        XCTAssertEqual(sut.messages.map(\.id.clientId), ["c1"])
        observation.cancel()
        await observation.value
    }

    /// Кейс: загружена страница сообщений.
    /// Ожидание: сообщения страницы переданы очереди — она уберёт те, что уже есть на сервере.
    func test_loadFirstPage_confirmsOutgoingInQueue() async {
        let sut = makeSUT()
        let page = [Message.make(id: 2, clientId: "c1"), .make(id: 1)]
        messageService.stubbedPages = [.success(MessagesPage(messages: page, nextBlockId: nil, hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(messageSendQueue.confirmedBatches, [page])
    }

    /// Кейс: тап по доставленному и по неотправленному сообщению.
    /// Ожидание: выбор действий показывается только для неотправленного.
    func test_didTapMessage_showsActionsForFailedOnly() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()
        messageSendQueue.outgoingMessages = [.stub(clientId: "a", status: .failed)]

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

    /// Кейс: отправленное сообщение пришло, пока грузилась первая страница, а ответ сервера собран до отправки.
    /// Ожидание: после ответа отправленное сообщение остаётся в списке — сверху, над сообщениями страницы.
    func test_sentMessage_duringFirstPageLoad_keepsSentMessage() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        messageService.onFetch = { await gate.wait() }
        let observation = Task { await sut.observeSentMessages() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }
        await yieldUntil { [unowned self] in messageSendQueue.subscriberCount == 1 }

        messageSendQueue.publishSent(.make(id: 2, clientId: "c1"))
        await yieldUntil { sut.messages.map(\.id.clientId) == ["c1"] }
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.id.clientId), ["c1", "client-1"])
        observation.cancel()
    }

    /// Кейс: сообщение отправлено, затем обновление вернуло первую страницу из более новых чужих сообщений —
    /// отправленное в неё не попало.
    /// Ожидание: лента показывает только первую страницу; отправленное не встаёт над более новыми сообщениями.
    func test_loadFirstPage_afterSend_pageNewerThanSent_hidesSentMessage() async {
        let sut = makeSUT()
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false)),
            .success(MessagesPage(messages: [.make(id: 4), .make(id: 3)], nextBlockId: 1, hasNext: true)),
        ]
        await sut.loadFirstPage()
        sut.handle(.messageReceived(.make(id: 2)))

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(4, 3))
    }

    // MARK: - События WebSocket

    /// Кейс: лента показана, событием пришло новое сообщение этой переписки.
    /// Ожидание: сообщение встало в ленту первым.
    func test_messageReceived_showsMessageFirst() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        sut.handle(.messageReceived(.make(id: 2, senderId: 2)))

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(2, 1))
    }

    /// Кейс: событием пришло сообщение другой переписки.
    /// Ожидание: лента не меняется.
    func test_messageReceived_otherConversation_isIgnored() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        sut.handle(.messageReceived(.make(id: 2, conversationId: 99)))

        XCTAssertEqual(sut.messages.map(\.id.clientId), clientIds(1))
    }

    /// Кейс: очередь опубликовала отправленное сообщение, затем пришло событие о нём же (сервер шлёт его и автору).
    /// Ожидание: сообщение в ленте одно — повторное применение ничего не меняет.
    func test_messageReceived_ownSentMessage_doesNotDuplicate() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()
        let observation = Task { await sut.observeSentMessages() }
        await yieldUntil { [unowned self] in messageSendQueue.subscriberCount == 1 }
        messageSendQueue.publishSent(.make(id: 2, clientId: "c1"))
        await yieldUntil { sut.messages.count == 2 }

        sut.handle(.messageReceived(.make(id: 2, clientId: "c1")))

        XCTAssertEqual(sut.messages.map(\.id.clientId), ["c1", "client-1"])
        observation.cancel()
    }

    /// Кейс: сообщение ленты отредактировано (событие), затем пришла его более старая версия (повтор события).
    /// Ожидание: показан новый текст, старая версия правку не откатывает.
    func test_messageEdited_replacesTextAndIgnoresOlderVersion() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.stub], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        sut.handle(.messageEdited(.editedStub))
        sut.handle(.messageReceived(.stub))

        XCTAssertEqual(sut.messages.map(\.text), [Message.editedStub.text])
    }

    /// Кейс: правка пришла событием, пока грузилась первая страница, а ответ сервера собран до правки.
    /// Ожидание: после ответа показан отредактированный текст — данные REST старше события.
    func test_messageEdited_duringFirstPageLoad_keepsEdit() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.stub], nextBlockId: nil, hasNext: false))]
        messageService.onFetch = { await gate.wait() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        sut.handle(.messageEdited(.editedStub))
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.text), [Message.editedStub.text])
    }

    /// Кейс: соединение с WebSocket (пере)установлено; на сервере появилось новое сообщение.
    /// Ожидание: самые новые сообщения заново запрошены с сервера — события без соединения могли потеряться.
    func test_connected_syncsFirstPage() async {
        let sut = makeSUT()
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false)),
            .success(MessagesPage(messages: [.make(id: 2), .make(id: 1)], nextBlockId: nil, hasNext: false)),
        ]
        await sut.loadFirstPage()

        sut.handle(.connected)

        await yieldUntil { sut.messages.map(\.id.clientId) == clientIds(2, 1) }
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: лента прокручена в историю (у первой страницы есть продолжение), соединение переустановлено.
    /// Ожидание: новое сообщение встало в начало, а загруженные ранее сообщения остались в ленте.
    func test_connected_keepsLoadedHistory() async {
        let sut = makeSUT()
        messageService.stubbedPages = [
            .success(MessagesPage(messages: [.make(id: 3), .make(id: 2)], nextBlockId: 1, hasNext: true)),
            .success(MessagesPage(messages: [.make(id: 4), .make(id: 3)], nextBlockId: 2, hasNext: true)),
        ]
        await sut.loadFirstPage()

        sut.handle(.connected)

        await yieldUntil { sut.messages.map(\.id.clientId) == clientIds(4, 3, 2) }
    }

    /// Кейс: экран подписан на события, сервис WebSocket прислал новое сообщение.
    /// Ожидание: оно появилось в ленте; после отмены подписки задача завершается.
    func test_observeRealtimeEvents_appliesEvents() async {
        let sut = makeSUT()
        let observation = Task { await sut.observeRealtimeEvents() }
        await yieldUntil { [unowned self] in realtimeService.subscriberCount == 1 }

        realtimeService.send(.messageReceived(.make(id: 5, senderId: 2)))

        await yieldUntil { sut.messages.map(\.id.clientId) == clientIds(5) }
        observation.cancel()
        await observation.value
    }

    // MARK: - Helpers

    /// Создаёт ViewModel над моками этого теста.
    /// - Parameter conversation: открытая переписка; по умолчанию — личная с собеседником 2.
    private func makeSUT(conversation: Conversation = .singleStub) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            messageService: messageService,
            messageStorage: messageStorage,
            messageSendQueue: messageSendQueue,
            sessionService: sessionService,
            userCache: userCache,
            localizationService: LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru),
            messageTextValidator: MessageTextValidator(),
            realtimeService: realtimeService
        )
    }

    /// `clientId` сообщений из `Message.make` с заданными `messageId`.
    /// - Parameter ids: `messageId` сообщений в порядке ленты.
    private func clientIds(_ ids: Int...) -> [String] {
        ids.map { "client-\($0)" }
    }
}
