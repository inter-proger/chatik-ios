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
    private var sessionService: SessionService!
    private var userCache: UserCacheServiceMock!
    private var realtimeService: RealtimeServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        messageService = MessageServiceMock()
        messageStorage = MessageStorageServiceMock()
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

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
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
        XCTAssertEqual(sut.messages.map(\.id), Array((1...14).reversed()))
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

        XCTAssertEqual(sut.messages.map(\.id), [3, 2, 1])
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

        XCTAssertEqual(sut.messages.map(\.id), [1])
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

        XCTAssertEqual(sut.messages.map(\.id), [1])
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

        await yieldUntil { sut.messages.map(\.id) == [1] }
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
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

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
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

        XCTAssertEqual(sut.messages.map(\.id), [1])
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

    /// Кейс: сообщение успешно отправлено.
    /// Ожидание: на сервер ушёл текст из поля, сообщение появилось первым в списке, сохранено в БД, поле очищено.
    func test_send_success_showsMessageAndClearsInput() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()
        messageService.stubbedSentMessage = .success(.make(id: 2, text: "Привет"))
        sut.messageText = "Привет"

        await sut.send()

        XCTAssertEqual(messageService.sentRequests.map(\.text), ["Привет"])
        XCTAssertEqual(messageService.sentRequests.map(\.conversationId), [Conversation.singleStub.id])
        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
        XCTAssertEqual(messageStorage.savedMessages.last?.id, 2)
        XCTAssertEqual(sut.messageText, "")
        XCTAssertFalse(sut.isEmpty)
    }

    /// Кейс: отправка не удалась.
    /// Ожидание: показано сообщение об ошибке, текст остался в поле, флаг отправки снят.
    func test_send_failure_keepsTextAndShowsError() async {
        let sut = makeSUT()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        sut.messageText = "Привет"

        await sut.send()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertEqual(sut.messageText, "Привет")
        XCTAssertFalse(sut.isSending)
    }

    /// Кейс: пока сообщение отправлялось, в поле дописали текст после отправленного.
    /// Ожидание: после успешной отправки в поле осталось только дописанное.
    func test_send_textTypedWhileSending_keepsTypedText() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 2, text: "Привет"))
        messageService.onSend = { await gate.wait() }
        sut.messageText = "Привет"

        sut.didTapSend()
        await yieldUntil { gate.isWaiting }
        sut.messageText = "Привет, как дела?"
        gate.open()
        await yieldUntil { !sut.isSending }

        XCTAssertEqual(sut.messageText, ", как дела?")
    }

    /// Кейс: пока сообщение отправлялось, начало текста в поле изменили.
    /// Ожидание: после успешной отправки поле не тронуто.
    func test_send_textChangedWhileSending_keepsField() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 2, text: "Привет"))
        messageService.onSend = { await gate.wait() }
        sut.messageText = "Привет"

        sut.didTapSend()
        await yieldUntil { gate.isWaiting }
        sut.messageText = "Пока"
        gate.open()
        await yieldUntil { !sut.isSending }

        XCTAssertEqual(sut.messageText, "Пока")
    }

    /// Кейс: запрос отправки выполняется.
    /// Ожидание: флаг отправки поднят, кнопка неактивна, повторное нажатие не отправляет второй запрос.
    func test_didTapSend_whileSending_ignoresRepeatedTap() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 2))
        messageService.onSend = { await gate.wait() }
        sut.messageText = "Привет"

        sut.didTapSend()
        await yieldUntil { gate.isWaiting }
        sut.didTapSend()

        XCTAssertTrue(sut.isSending)
        XCTAssertFalse(sut.isSendEnabled)
        gate.open()
        await yieldUntil { !sut.isSending }
        XCTAssertEqual(messageService.sentRequests.count, 1)
    }

    /// Кейс: сообщение отправлено, пока грузилась первая страница, а ответ сервера собран до отправки.
    /// Ожидание: после ответа отправленное сообщение остаётся в списке — сверху, над сообщениями страницы.
    func test_send_duringFirstPageLoad_keepsSentMessage() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        messageService.onFetch = { await gate.wait() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }
        messageService.stubbedSentMessage = .success(.make(id: 2))
        sut.messageText = "Привет"

        await sut.send()
        gate.open()
        await load.value

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
    }

    /// Кейс: два тапа по «Отправить» подряд, до того как задача отправки успела запуститься.
    /// Ожидание: флаг отправки поднят сразу после первого тапа, на сервер ушёл один запрос.
    func test_didTapSend_twiceBeforeTaskStarts_sendsOnce() async {
        let sut = makeSUT()
        messageService.stubbedSentMessage = .success(.make(id: 2))
        sut.messageText = "Привет"

        sut.didTapSend()
        sut.didTapSend()

        XCTAssertTrue(sut.isSending)
        await yieldUntil { !sut.isSending }
        XCTAssertEqual(messageService.sentRequests.count, 1)
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
        messageService.stubbedSentMessage = .success(.make(id: 2))
        sut.messageText = "Привет"
        await sut.send()

        await sut.loadFirstPage()

        XCTAssertEqual(sut.messages.map(\.id), [4, 3])
    }

    // MARK: - События WebSocket

    /// Кейс: лента показана, событием пришло новое сообщение этой переписки.
    /// Ожидание: сообщение встало в ленту первым.
    func test_messageReceived_showsMessageFirst() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        sut.handle(.messageReceived(.make(id: 2, senderId: 2)))

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
    }

    /// Кейс: событием пришло сообщение другой переписки.
    /// Ожидание: лента не меняется.
    func test_messageReceived_otherConversation_isIgnored() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()

        sut.handle(.messageReceived(.make(id: 2, conversationId: 99)))

        XCTAssertEqual(sut.messages.map(\.id), [1])
    }

    /// Кейс: сообщение отправлено с экрана, затем пришло событие о нём же (сервер шлёт его и автору).
    /// Ожидание: сообщение в ленте одно — повторное применение ничего не меняет.
    func test_messageReceived_ownSentMessage_doesNotDuplicate() async {
        let sut = makeSUT()
        messageService.stubbedPages = [.success(MessagesPage(messages: [.make(id: 1)], nextBlockId: nil, hasNext: false))]
        await sut.loadFirstPage()
        messageService.stubbedSentMessage = .success(.make(id: 2))
        sut.messageText = "Привет"
        await sut.send()

        sut.handle(.messageReceived(.make(id: 2)))

        XCTAssertEqual(sut.messages.map(\.id), [2, 1])
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

        await yieldUntil { sut.messages.map(\.id) == [2, 1] }
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

        await yieldUntil { sut.messages.map(\.id) == [4, 3, 2] }
    }

    /// Кейс: экран подписан на события, сервис WebSocket прислал новое сообщение.
    /// Ожидание: оно появилось в ленте; после отмены подписки задача завершается.
    func test_observeRealtimeEvents_appliesEvents() async {
        let sut = makeSUT()
        let observation = Task { await sut.observeRealtimeEvents() }
        await yieldUntil { [unowned self] in realtimeService.subscriberCount == 1 }

        realtimeService.send(.messageReceived(.make(id: 5, senderId: 2)))

        await yieldUntil { sut.messages.map(\.id) == [5] }
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
            sessionService: sessionService,
            userCache: userCache,
            localizationService: LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru),
            messageTextValidator: MessageTextValidator(),
            realtimeService: realtimeService
        )
    }
}
