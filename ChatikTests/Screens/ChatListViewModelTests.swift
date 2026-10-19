//
//  ChatListViewModelTests.swift
//  ChatikTests
//

import SwiftUI
import XCTest
@testable import Chatik

@MainActor
final class ChatListViewModelTests: XCTestCase {
    private var sessionService: SessionService!
    private var conversationList: ConversationListServiceMock!
    private var userCache: UserCacheServiceMock!
    private var draftService: MessageDraftServiceMock!
    private var unsentMessages: UnsentMessagePreviewProvidingMock!
    private var router: ChatListRouter!
    private var sleeper: RowsUpdateSleeper!
    private var sut: ChatListViewModel!
    /// Наблюдатель строк текущего `sut`; отменяется в `tearDown` и при замене `sut`.
    private var rowsObservation: Task<Void, Never>?

    override func setUp() async throws {
        try await super.setUp()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        conversationList = ConversationListServiceMock()
        userCache = UserCacheServiceMock()
        draftService = MessageDraftServiceMock()
        unsentMessages = UnsentMessagePreviewProvidingMock()
        router = ChatListRouter()
        sleeper = RowsUpdateSleeper()
        sut = makeSUT(now: { ServerTime.stub.date })
    }

    override func tearDown() async throws {
        await stopObservingRows()
        try await super.tearDown()
    }

    // MARK: - Список

    /// Кейс: в сервисе списка две переписки.
    /// Ожидание: строки показаны в порядке сервиса, с превью и временем.
    func test_conversations_mapsListInOrder() async {
        conversationList.conversations = [.groupStub, .singleStub]
        await observeRows()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id, Conversation.singleStub.id])
        XCTAssertEqual(sut.conversations.first?.preview, .message("Привет!"))
        XCTAssertFalse(sut.conversations.first?.time.isEmpty ?? true)
    }

    /// Кейс: список в сервисе изменился (переписка поднялась событием).
    /// Ожидание: экран узнаёт об изменении через Observation — строки перерисуются в новом порядке.
    func test_conversations_listChanged_notifiesObservers() async {
        conversationList.conversations = [.singleStub, .groupStub]
        await observeRows()
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.conversations } onChange: { changed.isSet = true }

        conversationList.conversations = [.groupStub, .singleStub]
        await yieldUntil { changed.isSet }

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id, Conversation.singleStub.id])
    }

    /// Кейс: в сервисе уже есть список (кэш из БД), когда создаётся ViewModel.
    /// Ожидание: строки готовы сразу — первый кадр экрана не ждёт наблюдателя.
    func test_init_existingList_buildsRowsImmediately() {
        conversationList.conversations = [.groupStub, .singleStub]

        sut = makeSUT(now: { ServerTime.stub.date })

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id, Conversation.singleStub.id])
    }

    // MARK: - Частота обновления строк

    /// Кейс: строки обновились; за интервал после этого список меняется трижды; затем интервал истёк.
    /// Ожидание: пока интервал не истёк, строки прежние; после — одно обновление с последней версией списка;
    /// пауза — `rowsUpdateInterval` (0,5 с).
    func test_observeConversations_changesWithinInterval_coalesced() async {
        sleeper.isAutomatic = false
        conversationList.conversations = [.make(id: 1)]
        startObservingRows()
        await yieldUntil { [unowned self] in sleeper.isWaiting }
        let updates = RowsUpdateCounter(sut)

        conversationList.conversations = [.make(id: 2), .make(id: 1)]
        conversationList.conversations = [.make(id: 3), .make(id: 2), .make(id: 1)]
        conversationList.conversations = [.make(id: 4), .make(id: 3), .make(id: 2), .make(id: 1)]
        await yieldTimes()
        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertEqual(updates.count, 0)
        sleeper.release()
        await yieldUntil { updates.count == 1 }
        await yieldTimes()

        XCTAssertEqual(sut.conversations.map(\.id), [4, 3, 2, 1])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(sleeper.requested.first, ChatListViewModel.rowsUpdateInterval)
    }

    /// Кейс: после обновления интервал истёк, а изменений не было; затем список изменился.
    /// Ожидание: изменение после паузы применяется сразу, без нового ожидания интервала.
    func test_observeConversations_changeAfterQuietInterval_appliedImmediately() async {
        sleeper.isAutomatic = false
        startObservingRows()
        await yieldUntil { [unowned self] in sleeper.isWaiting }
        sleeper.release()
        await yieldTimes()

        conversationList.conversations = [.make(id: 1)]
        await yieldUntil { [unowned self] in !sut.conversations.isEmpty }

        XCTAssertEqual(sut.conversations.map(\.id), [1])
        XCTAssertEqual(sleeper.requested.count, 2)
    }

    /// Кейс: список изменился, пока наблюдатель строк не запущен (экран скрыт — открыта переписка); затем экран
    /// снова показан.
    /// Ожидание: при запуске наблюдателя строки собраны сразу — с изменением, пропущенным за время скрытия.
    func test_observeConversations_restarted_rebuildsImmediately() async {
        await observeRows()
        await stopObservingRows()

        conversationList.conversations = [.make(id: 5)]
        XCTAssertTrue(sut.conversations.isEmpty)
        await observeRows()

        XCTAssertEqual(sut.conversations.map(\.id), [5])
    }

    /// Кейс: наблюдатель строк ждёт конца интервала, задачу отменили (экран ушёл).
    /// Ожидание: наблюдатель завершился.
    func test_observeConversations_cancelled_finishes() async {
        sleeper.isAutomatic = false
        startObservingRows()
        await yieldUntil { [unowned self] in sleeper.isWaiting }

        rowsObservation?.cancel()
        sleeper.release()
        await rowsObservation?.value
        rowsObservation = nil
    }

    /// Кейс: идёт первая синхронизация, список пуст и ещё не загружен; затем она закончилась пустым списком.
    /// Ожидание: пока идёт синхронизация — прелоадер и индикатор обновления, «пусто» не показывается;
    /// после — «пусто» без прелоадера.
    func test_isEmpty_whileSyncing_isFalse() {
        conversationList.isSyncing = true

        XCTAssertTrue(sut.isSyncing)
        XCTAssertTrue(sut.isLoadingFirstPage)
        XCTAssertFalse(sut.isEmpty)
        conversationList.isSyncing = false
        conversationList.isLoaded = true
        XCTAssertFalse(sut.isLoadingFirstPage)
        XCTAssertTrue(sut.isEmpty)
    }

    /// Кейс: список пуст, ни разу не загружался и синхронизация не идёт — например, WebSocket ещё не подключился
    /// или первая загрузка не удалась.
    /// Ожидание: «Нет чатов» не показывается — пустой список до первой загрузки ещё ничего не значит.
    func test_isEmpty_notLoaded_isFalse() {
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: идёт синхронизация поверх списка, однажды загруженного с сервера, — сейчас пустого.
    /// Ожидание: прелоадера по центру нет — об обновлении говорит заголовок.
    func test_isLoadingFirstPage_loadedList_isFalse() {
        conversationList.isLoaded = true
        conversationList.isSyncing = true

        XCTAssertFalse(sut.isLoadingFirstPage)
        XCTAssertFalse(sut.isEmpty)
    }

    /// Кейс: идёт синхронизация, а список уже показан из кэша.
    /// Ожидание: экран не пуст, индикатор обновления показан.
    func test_isSyncing_withCachedList_isNotEmpty() {
        conversationList.conversations = [.singleStub]
        conversationList.isSyncing = true
        sut = makeSUT(now: { ServerTime.stub.date })

        XCTAssertTrue(sut.isSyncing)
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: идёт первая синхронизация, строк нет; первая страница пришла, пока строки ждут конца интервала.
    /// Ожидание: прелоадер не пропадает, пока строки не догнали список, — экран не остаётся пустым; «пусто» не
    /// показывается; после обновления строк прелоадера нет.
    func test_isLoadingFirstPage_rowsBehindLoadedList_isTrue() async {
        conversationList.isSyncing = true

        conversationList.conversations = [.make(id: 1)]
        conversationList.isLoaded = true
        conversationList.isSyncing = false

        XCTAssertTrue(sut.isLoadingFirstPage)
        XCTAssertFalse(sut.isEmpty)
        await observeRows()
        XCTAssertFalse(sut.isLoadingFirstPage)
        XCTAssertEqual(sut.conversations.map(\.id), [1])
    }

    /// Кейс: строки показаны; список в сервисе стал пустым (pull-to-refresh), пока строки ждут конца интервала.
    /// Ожидание: «Нет чатов» не показывается поверх прежних строк; после обновления строк — показывается.
    func test_isEmpty_rowsBehindEmptiedList_isFalse() async {
        conversationList.conversations = [.make(id: 1)]
        conversationList.isLoaded = true
        sut = makeSUT(now: { ServerTime.stub.date })

        conversationList.conversations = []

        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.isLoadingFirstPage)
        await observeRows()
        XCTAssertTrue(sut.isEmpty)
    }

    /// Кейс: экран открыт, синхронизация прошла успешно.
    /// Ожидание: сервис списка получил запрос `synchronizeIfNeeded()`, ошибки нет.
    func test_loadIfNeeded_success_callsServiceWithoutError() async {
        await sut.loadIfNeeded()

        XCTAssertEqual(conversationList.synchronizeIfNeededCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: синхронизация при открытии экрана упала с ошибкой сети.
    /// Ожидание: показано сообщение об отсутствии соединения.
    func test_loadIfNeeded_transportError_showsError() async {
        conversationList.stubbedSynchronizeIfNeededError = NetworkError.transport(URLError(.notConnectedToInternet))

        await sut.loadIfNeeded()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    /// Кейс: синхронизацию при открытии экрана прервала новая синхронизация.
    /// Ожидание: ошибка не показывается.
    func test_loadIfNeeded_cancelled_showsNoError() async {
        conversationList.stubbedSynchronizeIfNeededError = CancellationError()

        await sut.loadIfNeeded()

        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: переписка поднялась «сегодня»; экран открыт, затем наступил следующий день (`NSCalendarDayChanged`).
    /// Ожидание: время строки сменилось — вчерашняя переписка показывает не только время, но и дату.
    func test_observeDayChanges_dayChanged_reformatsTime() async {
        let clock = DateBox(date: ServerTime.stub.date)
        let notificationCenter = NotificationCenter()
        conversationList.conversations = [.singleStub.with(position: .stub, lastMessage: nil)]
        await replaceSUT(makeSUT(now: { clock.date }))
        await observeRows()
        let todayTime = sut.conversations.first?.time
        let observation = Task { [sut] in await sut!.observeDayChanges(notificationCenter: notificationCenter) }
        await yieldTimes()

        clock.date = clock.date.addingTimeInterval(24 * 60 * 60)
        for _ in 0..<50 where sut.conversations.first?.time == todayTime {
            notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
            await yieldTimes(5)
        }
        observation.cancel()

        XCTAssertNotEqual(sut.conversations.first?.time, todayTime)
    }

    // MARK: - Кэш строк

    /// Кейс: строки показаны; затем в списке изменилась одна переписка (поднялась с новым сообщением).
    /// Ожидание: заново собрана только её строка, остальные взяты из кэша; при повторном чтении без изменений
    /// ничего не собирается.
    func test_conversations_oneChanged_rebuildsOnlyChangedRow() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        conversationList.conversations = [.make(id: 1), .make(id: 2), .make(id: 3)]
        await observeRows()
        recorder.ids = []

        conversationList.conversations = [
            Conversation.make(id: 2).with(position: .stub(10), lastMessage: .make(id: 5, updatedAt: .stub(10))),
            .make(id: 1),
            .make(id: 3),
        ]
        await yieldUntil { [unowned self] in sut.conversations.first?.id == 2 }
        await yieldTimes()

        XCTAssertEqual(sut.conversations.map(\.id), [2, 1, 3])
        XCTAssertEqual(recorder.ids, [2])
    }

    /// Кейс: строка личной переписки показана, пока собеседник грузится; затем собеседник загрузился.
    /// Ожидание: строка собрана заново — с именем собеседника.
    func test_conversations_opponentLoaded_rebuildsRow() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        conversationList.conversations = [.singleStub, .make(id: 9)]
        await observeRows()
        recorder.ids = []

        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Пётр", avatar: nil))
        await yieldUntil { [unowned self] in sut.conversations.first?.title == "Пётр" }

        XCTAssertEqual(recorder.ids, [Conversation.singleStub.id])
    }

    /// Кейс: строки показаны; сменился язык интерфейса.
    /// Ожидание: кэш сброшен — все строки собраны заново.
    func test_conversations_languageChanged_rebuildsAllRows() async {
        let recorder = RowBuildRecorder()
        let localizationService = LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru)
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, localizationService: localizationService, makeRow: recorder.build))
        conversationList.conversations = [.make(id: 1), .make(id: 2)]
        await observeRows()
        recorder.ids = []

        await localizationService.setLanguage(.en)
        await yieldUntil { recorder.ids.count == 2 }

        XCTAssertEqual(recorder.ids, [1, 2])
    }

    /// Кейс: строки показаны; «сейчас» сдвинулось в пределах того же дня (повторное открытие экрана).
    /// Ожидание: строки взяты из кэша — внутри дня формат времени не меняется.
    func test_conversations_sameDayReferenceChanged_keepsCache() async {
        let recorder = RowBuildRecorder()
        let clock = DateBox(date: Calendar.current.startOfDay(for: ServerTime.stub.date).addingTimeInterval(60 * 60))
        await replaceSUT(makeSUT(now: { clock.date }, makeRow: recorder.build))
        conversationList.conversations = [.make(id: 1)]
        await observeRows()
        recorder.ids = []

        clock.date = clock.date.addingTimeInterval(60 * 60)
        let observation = Task { [sut] in await sut!.observeDayChanges(notificationCenter: NotificationCenter()) }
        await yieldUntil { [unowned self] in sut.referenceDate == clock.date }
        observation.cancel()
        await yieldTimes()

        XCTAssertTrue(recorder.ids.isEmpty)
    }

    /// Кейс: pull-to-refresh, обновление прошло успешно.
    /// Ожидание: обновление запрошено у сервиса списка, ошибки нет.
    func test_refresh_success_callsServiceWithoutError() async {
        await sut.refresh()

        XCTAssertEqual(conversationList.refreshCallCount, 1)
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: pull-to-refresh завершился ошибкой сети.
    /// Ожидание: показано сообщение об отсутствии соединения.
    func test_refresh_transportError_showsError() async {
        conversationList.stubbedRefreshError = NetworkError.transport(URLError(.notConnectedToInternet))

        await sut.refresh()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    /// Кейс: pull-to-refresh прервала новая синхронизация.
    /// Ожидание: ошибка не показывается — список обновит сама синхронизация.
    func test_refresh_cancelled_showsNoError() async {
        conversationList.stubbedRefreshError = CancellationError()

        await sut.refresh()

        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: на экране появилась строка переписки.
    /// Ожидание: сервис списка получил её id — решать, грузить ли следующую страницу, ему.
    func test_prefetchNextPage_forwardsConversationId() {
        sut.prefetchNextPageIfNeeded(currentConversation: ChatRowDisplayModel(id: 7, title: "", avatarURL: nil))

        XCTAssertEqual(conversationList.nextPageRequests, [7])
    }

    /// Кейс: сервис списка грузит следующую страницу.
    /// Ожидание: экран показывает индикатор подгрузки.
    func test_isLoadingNextPage_readsService() {
        conversationList.isLoadingNextPage = true

        XCTAssertTrue(sut.isLoadingNextPage)
    }

    // MARK: - Черновики

    /// Кейс: у одной из переписок есть черновик.
    /// Ожидание: её строка показывает черновик вместо последнего сообщения, остальные — последнее сообщение.
    func test_conversations_draft_replacesPreview() async {
        draftService.drafts = [Conversation.groupStub.id: "Черновик"]
        conversationList.conversations = [.groupStub, .make(id: 9)]

        await observeRows()

        guard case let .labeled(text) = sut.conversations.first?.preview else { return XCTFail("Превью не черновик") }
        XCTAssertEqual(String(text.characters), "\(ChatListStrings.rowDraftPrefix) Черновик")
        XCTAssertEqual(sut.conversations.last?.preview, .message(ChatListStrings.rowNoMessages))
    }

    /// Кейс: строки показаны; у одной переписки появился черновик.
    /// Ожидание: экран узнаёт об этом через Observation — её строка собрана заново, а не взята из кэша;
    /// остальные строки из кэша.
    func test_conversations_draftChanged_rebuildsRow() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        conversationList.conversations = [.make(id: 1), .make(id: 2)]
        await observeRows()
        recorder.ids = []

        draftService.drafts[2] = "Черновик"
        await yieldUntil { [unowned self] in
            guard case .labeled = sut.conversations.last?.preview else { return false }
            return true
        }

        XCTAssertEqual(recorder.ids, [2])
    }

    // MARK: - Неотправленные сообщения

    /// Кейс: у переписки есть и неотправленное сообщение, и черновик; у другой — только черновик.
    /// Ожидание: первая строка собрана с неотправленным и показывает «Не отправлено:», вторая — с черновиком.
    func test_conversations_failed_takesPriorityOverDraft() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        unsentMessages.lastFailedTexts = [1: "Не ушло"]
        draftService.drafts = [1: "Черновик", 2: "Другой черновик"]
        conversationList.conversations = [.make(id: 1), .make(id: 2)]

        await observeRows()

        XCTAssertEqual(recorder.localPreviews.suffix(2), [.failed("Не ушло"), .draft("Другой черновик")])
        guard case let .labeled(text) = sut.conversations.first?.preview else { return XCTFail("Превью не неотправленное") }
        XCTAssertEqual(String(text.characters), "\(ChatListStrings.rowFailedPrefix) Не ушло")
    }

    /// Кейс: строки показаны; в одной переписке сообщение стало неотправленным, затем его удалили.
    /// Ожидание: каждый раз эта строка собрана заново, а не взята из кэша; остальные строки из кэша; после удаления
    /// строка снова показывает последнее сообщение.
    func test_conversations_failedChanged_rebuildsRow() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        conversationList.conversations = [.make(id: 1), .make(id: 2)]
        await observeRows()
        recorder.ids = []

        unsentMessages.lastFailedTexts[2] = "Не ушло"
        await yieldUntil { [unowned self] in
            guard case .labeled = sut.conversations.last?.preview else { return false }
            return true
        }
        unsentMessages.lastFailedTexts[2] = nil
        await yieldUntil { [unowned self] in sut.conversations.last?.preview == .message(ChatListStrings.rowNoMessages) }

        XCTAssertEqual(recorder.ids, [2, 2])
    }

    // MARK: - Редактирование

    /// Кейс: в переписке незавершённое редактирование, неотправленное сообщение и черновик; в другой — только
    /// черновик.
    /// Ожидание: первая строка показывает «Редактирование активно», вторая — черновик.
    func test_conversations_editing_takesPriority() async {
        let recorder = RowBuildRecorder()
        await replaceSUT(makeSUT(now: { ServerTime.stub.date }, makeRow: recorder.build))
        unsentMessages.lastFailedTexts = [1: "Не ушло"]
        draftService.drafts = [1: "Черновик", 2: "Другой черновик"]
        draftService.edits = [1: MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")]
        conversationList.conversations = [.make(id: 1), .make(id: 2)]

        await observeRows()

        XCTAssertEqual(recorder.localPreviews.suffix(2), [.editing, .draft("Другой черновик")])
        guard case let .labeled(text) = sut.conversations.first?.preview else { return XCTFail("Превью не редактирование") }
        XCTAssertEqual(String(text.characters), ChatListStrings.rowEditing)
    }

    /// Кейс: строки показаны; режим редактирования в переписке выключается (запрос завершился после ухода
    /// с экрана).
    /// Ожидание: строка собрана заново и показывает черновик вместо «Редактирование активно».
    func test_conversations_editingEnded_rebuildsRow() async {
        draftService.drafts = [1: "Черновик"]
        draftService.edits = [1: MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")]
        conversationList.conversations = [.make(id: 1)]
        await observeRows()

        draftService.endEditing(messageId: 15, conversationId: 1, userId: 1)

        await yieldUntil { [unowned self] in
            guard case let .labeled(text) = sut.conversations.first?.preview else { return false }
            return String(text.characters) == "\(ChatListStrings.rowDraftPrefix) Черновик"
        }
        guard case let .labeled(text) = sut.conversations.first?.preview else { return XCTFail("Превью не черновик") }
        XCTAssertEqual(String(text.characters), "\(ChatListStrings.rowDraftPrefix) Черновик")
    }

    // MARK: - Создание и выбор

    /// Кейс: экран создания завершился созданной перепиской.
    /// Ожидание: переписка передана сервису списка и открыта.
    func test_didCreateConversation_appliesAndOpens() {
        sut.didCreateConversation(.singleStub)

        XCTAssertEqual(conversationList.applied, [.singleStub])
        XCTAssertEqual(router.path, [.conversation(.singleStub)])
    }

    /// Кейс: тап по строке переписки из списка.
    /// Ожидание: открыт экран этой переписки, строка выбрана.
    func test_didSelectConversation_opensAndSelects() async throws {
        conversationList.conversations = [.singleStub, .groupStub]
        await observeRows()

        sut.didSelectConversation(try XCTUnwrap(sut.conversations.last))

        XCTAssertEqual(router.path, [.conversation(.groupStub)])
        XCTAssertEqual(sut.selectedConversationId, Conversation.groupStub.id)
    }

    /// Кейс: открытую переписку закрыли — экран убран из стека навигации.
    /// Ожидание: выбор строки снят.
    func test_selectedConversationId_conversationClosed_isNil() async throws {
        conversationList.conversations = [.singleStub]
        await observeRows()
        sut.didSelectConversation(try XCTUnwrap(sut.conversations.first))

        router.path.removeLast()

        XCTAssertNil(sut.selectedConversationId)
    }

    /// Кейс: поверх списка открыт профиль, а не переписка.
    /// Ожидание: ни одна строка не выбрана.
    func test_selectedConversationId_profileOpened_isNil() {
        sut.didTapProfile()

        XCTAssertNil(sut.selectedConversationId)
    }

    /// Кейс: тап по строке, переписки которой уже нет в списке.
    /// Ожидание: ничего не открывается.
    func test_didSelectConversation_unknownRow_doesNothing() {
        sut.didSelectConversation(ChatRowDisplayModel(id: 999, title: "", avatarURL: nil))

        XCTAssertTrue(router.path.isEmpty)
    }

    // MARK: - Собеседники

    /// Кейс: личная переписка, её собеседник уже есть в кэше пользователей.
    /// Ожидание: заголовок строки — имя собеседника из кэша.
    func test_conversations_opponentInCache_usesCachedName() async {
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))
        conversationList.conversations = [.singleStub]
        await observeRows()

        XCTAssertEqual(sut.conversations.first?.title, "Petr Sidorov")
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, false)
    }

    /// Кейс: собеседник догрузился в кэш уже после того, как строка показана с заглушкой.
    /// Ожидание: экран узнаёт об изменении через Observation, строка показывает имя.
    func test_conversations_opponentLoadedLater_updatesRow() async {
        conversationList.conversations = [.singleStub]
        await observeRows()
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, true)
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.conversations } onChange: { changed.isSet = true }

        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))
        await yieldUntil { changed.isSet }

        XCTAssertEqual(sut.conversations.first?.title, "Petr Sidorov")
    }

    // MARK: - Профиль и меню

    /// Кейс: у пользователя сессии нет аватара.
    /// Ожидание: URL аватара `nil` — кнопка профиля показывает изображение по умолчанию.
    func test_avatarURL_withoutAvatar_isNil() {
        XCTAssertNil(sut.avatarURL)
    }

    /// Кейс: у аватара есть уменьшенная копия.
    /// Ожидание: для кнопки профиля берётся URL уменьшенной копии.
    func test_avatarURL_withSmallCopy_returnsSmallURL() async {
        await sessionService.update(user: User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub))

        XCTAssertEqual(sut.avatarURL, RemoteFile.stub.smallURL)
    }

    /// Кейс: у аватара нет уменьшенной копии.
    /// Ожидание: для кнопки профиля берётся полноразмерный URL.
    func test_avatarURL_withoutSmallCopy_returnsFullURL() async {
        let avatar = RemoteFile(fileId: 1, type: .image, url: RemoteFile.stub.url, size: 1, filename: "a.jpg", fileExtension: "jpg", smallURL: nil)
        await sessionService.update(user: User(userId: 1, login: "ivan", name: "Ivan", avatar: avatar))

        XCTAssertEqual(sut.avatarURL, RemoteFile.stub.url)
    }

    /// Кейс: нажатие на кнопку-аватар.
    /// Ожидание: в путь навигации добавлен экран профиля.
    func test_didTapProfile_pushesProfileRoute() {
        sut.didTapProfile()

        XCTAssertEqual(router.path, [.profile])
    }

    /// Кейс: выбран пункт «Личный диалог» в меню создания.
    /// Ожидание: модально открыт экран создания личного диалога.
    func test_didTapCreateSingleConversation_presentsSheet() {
        sut.didTapCreateSingleConversation()

        XCTAssertEqual(router.presentedSheet, .createSingleConversation)
    }

    // MARK: - Helpers

    /// Создаёт ViewModel над моками теста.
    /// - Parameters:
    ///   - now: текущее время.
    ///   - localizationService: язык; по умолчанию — русский.
    ///   - makeRow: сборка строки; по умолчанию — настоящая.
    private func makeSUT(
        now: @escaping () -> Date,
        localizationService: LocalizationServiceProtocol? = nil,
        makeRow: ChatListViewModel.RowBuilder? = nil
    ) -> ChatListViewModel {
        ChatListViewModel(
            conversationList: conversationList,
            sessionService: sessionService,
            userCache: userCache,
            draftService: draftService,
            unsentMessages: unsentMessages,
            localizationService: localizationService ?? LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru),
            router: router,
            now: now,
            makeRow: makeRow ?? { ChatRowDisplayModel(conversation: $0, opponent: $1, localPreview: $2, timeFormatter: $3) },
            sleep: { [sleeper] in try await sleeper!.sleep($0) }
        )
    }

    /// Заменяет `sut`, останавливая наблюдатель строк прежнего.
    /// - Parameter viewModel: новый `sut`.
    private func replaceSUT(_ viewModel: ChatListViewModel) async {
        await stopObservingRows()
        sut = viewModel
    }

    /// Запускает наблюдатель строк `sut`, как это делает экран.
    private func startObservingRows() {
        rowsObservation = Task { [sut] in await sut!.observeConversations() }
    }

    /// Запускает наблюдатель строк, если он не запущен, и даёт ему применить текущее состояние.
    private func observeRows() async {
        if rowsObservation == nil {
            startObservingRows()
        }
        await yieldTimes()
    }

    /// Останавливает наблюдатель строк и дожидается его завершения.
    private func stopObservingRows() async {
        rowsObservation?.cancel()
        sleeper?.release()
        await rowsObservation?.value
        rowsObservation = nil
    }
}

/// Изменяемое «сейчас» для теста смены дня.
private final class DateBox {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

/// Флаг срабатывания `onChange` из `withObservationTracking`.
private final class ObservationFlag: @unchecked Sendable {
    var isSet = false
}

/// Сборка строк, запоминающая, какие строки собраны.
@MainActor
private final class RowBuildRecorder {
    /// `conversationId` собранных строк по порядку.
    var ids: [Int] = []
    /// Локальные состояния, с которыми собраны строки, по порядку.
    var localPreviews: [ChatRowLocalPreview?] = []

    /// Собирает строку настоящей сборкой и запоминает её id и локальное состояние.
    /// - Parameters:
    ///   - conversation: переписка.
    ///   - opponent: собеседник из кэша.
    ///   - localPreview: неотправленное сообщение или черновик переписки.
    ///   - timeFormatter: формат времени.
    func build(
        _ conversation: Conversation,
        _ opponent: CachedUser?,
        _ localPreview: ChatRowLocalPreview?,
        _ timeFormatter: MessageTimeFormatter
    ) -> ChatRowDisplayModel {
        ids.append(conversation.id)
        localPreviews.append(localPreview)
        return ChatRowDisplayModel(conversation: conversation, opponent: opponent, localPreview: localPreview, timeFormatter: timeFormatter)
    }
}

/// Ожидание между обновлениями строк: по умолчанию завершается сразу; в ручном режиме ждёт `release()`.
@MainActor
private final class RowsUpdateSleeper {
    /// `true` — ожидание завершается сразу.
    var isAutomatic = true
    /// Запрошенные паузы по порядку.
    private(set) var requested: [Duration] = []
    private let gate = Gate()

    /// `true`, пока наблюдатель ждёт `release()`.
    var isWaiting: Bool {
        gate.isWaiting
    }

    /// Пауза: в ручном режиме длится до `release()`; отменённая задача завершает её ошибкой.
    /// - Parameter duration: длительность паузы.
    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        if !isAutomatic {
            await gate.wait()
        }
        try Task.checkCancellation()
    }

    /// Завершает идущую паузу.
    func release() {
        gate.open()
    }
}

/// Считает обновления строк ViewModel через Observation.
@MainActor
private final class RowsUpdateCounter {
    /// Сколько раз изменились строки.
    private(set) var count = 0
    private let viewModel: ChatListViewModel

    /// - Parameter viewModel: ViewModel, за строками которой следит счётчик.
    init(_ viewModel: ChatListViewModel) {
        self.viewModel = viewModel
        track()
    }

    /// Подписывается на следующее изменение строк.
    private func track() {
        withObservationTracking { _ = viewModel.conversations } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.count += 1
                self?.track()
            }
        }
    }
}
