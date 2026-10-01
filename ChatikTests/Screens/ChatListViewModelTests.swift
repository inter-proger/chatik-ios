//
//  ChatListViewModelTests.swift
//  ChatikTests
//

import SwiftUI
import XCTest
@testable import Chatik

@MainActor
final class ChatListViewModelTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var userDefaultsService: UserDefaultsServiceMock!
    private var sessionService: SessionService!
    private var conversationService: ConversationServiceMock!
    private var conversationStorage: ConversationStorageServiceMock!
    private var userCache: UserCacheServiceMock!
    private var router: ChatListRouter!
    private var sut: ChatListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        networkService = NetworkServiceMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        conversationService = ConversationServiceMock()
        conversationStorage = ConversationStorageServiceMock()
        userCache = UserCacheServiceMock()
        router = ChatListRouter()
        sut = ChatListViewModel(
            authService: AuthService(networkService: networkService),
            sessionService: sessionService,
            conversationService: conversationService,
            conversationStorage: conversationStorage,
            userCache: userCache,
            router: router
        )
    }

    // MARK: - Список

    /// Кейс: сервер вернул страницу переписок.
    /// Ожидание: список показан в порядке ответа сервера, флаг первой загрузки снят.
    func test_loadFirstPage_success_showsConversations() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub, .groupStub], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id, Conversation.groupStub.id])
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: первая страница грузится.
    /// Ожидание: флаг загрузки первой страницы поднят, список считается не пустым.
    func test_loadFirstPage_whileLoading_setsLoadingFlag() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        var isLoadingDuringRequest = false
        var isEmptyDuringRequest = true
        conversationService.onRequest = { [unowned self] in
            isLoadingDuringRequest = sut.isLoadingFirstPage
            isEmptyDuringRequest = sut.isEmpty
        }

        await sut.loadFirstPage()

        XCTAssertTrue(isLoadingDuringRequest)
        XCTAssertFalse(isEmptyDuringRequest)
    }

    /// Кейс: сервер вернул пустую страницу.
    /// Ожидание: список пуст — экран показывает сообщение об отсутствии чатов.
    func test_loadFirstPage_emptyPage_isEmpty() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertTrue(sut.isEmpty)
    }

    /// Кейс: транспортная ошибка при загрузке первой страницы.
    /// Ожидание: показано сообщение об ошибке, флаг загрузки снят.
    func test_loadFirstPage_transportError_showsError() async {
        conversationService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: повторная загрузка (pull-to-refresh) после того, как список уже был показан.
    /// Ожидание: список заменяется новой страницей, а не дописывается.
    func test_loadFirstPage_again_replacesConversations() async {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: [.singleStub], hasNext: false)),
            .success(ConversationsPage(conversations: [.groupStub], hasNext: false)),
        ]

        await sut.loadFirstPage()
        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id])
    }

    // MARK: - Локальная БД

    /// Кейс: в локальной БД есть переписки, экран открывается.
    /// Ожидание: до ответа сервера показаны переписки из БД, после — они заменены ответом сервера.
    func test_loadFirstPage_withCache_showsCacheThenNetwork() async {
        let gate = Gate()
        conversationStorage.stubbedConversations = .success([.groupStub])
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        conversationService.onRequest = { await gate.wait() }
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        await yieldUntil { [unowned self] in sut.conversations.map(\.id) == [Conversation.groupStub.id] }
        gate.open()
        await load.value

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id])
    }

    /// Кейс: экран открывается, в локальной БД может быть сколько угодно переписок.
    /// Ожидание: из БД читается не больше одной страницы — экрану до ответа сервера нужно только начало списка.
    func test_loadFirstPage_readsCacheWithinPageSize() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(conversationStorage.fetchLatestLimits, [ChatListViewModel.pageSize])
    }

    /// Кейс: в локальной БД есть переписки, сервер недоступен.
    /// Ожидание: на экране остаются переписки из БД, показано сообщение об ошибке.
    func test_loadFirstPage_withCache_transportError_keepsCachedConversations() async {
        conversationStorage.stubbedConversations = .success([.groupStub])
        conversationService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id])
        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    /// Кейс: чтение локальной БД завершилось ошибкой.
    /// Ожидание: ошибка БД пользователю не показывается, список показан по ответу сервера.
    func test_loadFirstPage_cacheReadError_showsNetworkWithoutError() async {
        conversationStorage.stubbedConversations = .failure(CocoaError(.fileReadCorruptFile))
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id])
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: pull-to-refresh, когда список уже показан.
    /// Ожидание: БД повторно не читается — до ответа на экране остаётся текущий список.
    func test_loadFirstPage_again_doesNotReadCache() async {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: [.singleStub], hasNext: false)),
            .success(ConversationsPage(conversations: [.groupStub], hasNext: false)),
        ]
        await sut.loadFirstPage()
        var isCacheRead = false
        conversationStorage.onFetchLatest = { isCacheRead = true }

        await sut.loadFirstPage()

        XCTAssertFalse(isCacheRead)
    }

    /// Кейс: сервер вернул первую и следующую страницы.
    /// Ожидание: обе страницы сохранены в БД с признаком первой страницы — от него зависит, какие
    /// переписки удаляются из БД.
    func test_loadPages_savesPagesToStorage() async throws {
        let firstPage = ConversationsPage(conversations: makeConversations(ids: Array((1...30).reversed())), hasNext: true)
        let nextPage = ConversationsPage(conversations: makeConversations(ids: [0]), hasNext: false)
        conversationService.stubbedPages = [.success(firstPage), .success(nextPage)]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(conversationStorage.savedPages.map(\.page), [firstPage, nextPage])
        XCTAssertEqual(conversationStorage.savedPages.map(\.isFirstPage), [true, false])
    }

    /// Кейс: сохранение страницы в БД завершилось ошибкой.
    /// Ожидание: страница всё равно показана, ошибка БД пользователю не показывается.
    func test_loadFirstPage_saveError_showsConversationsWithoutError() async {
        conversationStorage.stubbedSaveError = CocoaError(.fileWriteUnknown)
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id])
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: создана новая переписка.
    /// Ожидание: она сохранена в БД — чтобы была в списке и без сети.
    func test_didCreateConversation_savesToStorage() async {
        sut.didCreateConversation(.singleStub)
        await yieldUntil { [unowned self] in !conversationStorage.savedConversations.isEmpty }

        XCTAssertEqual(conversationStorage.savedConversations, [.singleStub])
    }

    // MARK: - Собеседники

    /// Кейс: загружена личная переписка, её собеседник уже есть в кэше пользователей.
    /// Ожидание: заголовок строки — имя собеседника из кэша.
    func test_conversations_opponentInCache_usesCachedName() async {
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.first?.title, "Petr Sidorov")
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, false)
    }

    /// Кейс: собеседник догрузился в кэш уже после того, как список показан с заглушкой.
    /// Ожидание: экран узнаёт об изменении через Observation, строка показывает имя без перезагрузки списка.
    func test_conversations_opponentLoadedLater_updatesRow() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        await sut.loadFirstPage()
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, true)
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.conversations } onChange: { changed.isSet = true }

        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))

        XCTAssertTrue(changed.isSet)
        XCTAssertEqual(sut.conversations.first?.title, "Petr Sidorov")
        XCTAssertEqual(conversationService.requests.count, 1)
    }

    /// Кейс: экран открывается, в локальной БД есть личная и групповая переписки.
    /// Ожидание: кэшу пользователей передан собеседник личной переписки — у ответа БД нет action `users`.
    func test_loadFirstPage_withCache_loadsCachedOpponents() async {
        conversationStorage.stubbedConversations = .success([.singleStub, .groupStub])
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [], hasNext: false))]

        await sut.loadFirstPage()
        await yieldUntil { [unowned self] in !userCache.loadRequests.isEmpty }

        XCTAssertEqual(userCache.loadRequests, [[2]])
    }

    // MARK: - Следующие страницы

    /// Кейс: первая страница полная, на экране появилась одна из последних переписок списка.
    /// Ожидание: следующая страница запрошена со сдвигом, равным числу уже загруженных переписок, и дописана к списку.
    func test_prefetchNextPage_nearEnd_appendsNextPage() async throws {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: [31]), hasNext: false)),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(conversationService.requests.last?.offset, 30)
        XCTAssertEqual(sut.conversations.map(\.id), Array(1...31))
    }

    /// Кейс: первая страница полная, на экране переписка из начала списка.
    /// Ожидание: следующая страница не запрашивается.
    func test_prefetchNextPage_farFromEnd_doesNotLoad() async throws {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true))]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.first))

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertEqual(conversationService.requests.count, 1)
    }

    /// Кейс: сервер ответил `hasNext: false` — эта страница последняя.
    /// Ожидание: при показе последней переписки следующая страница не запрашивается.
    func test_prefetchNextPage_lastPage_doesNotLoad() async throws {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: makeConversations(ids: [1, 2]), hasNext: false))]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertEqual(conversationService.requests.count, 1)
    }

    /// Кейс: транспортная ошибка при загрузке следующей страницы.
    /// Ожидание: список остаётся прежним, показано сообщение об ошибке, а повторные появления последней строки
    /// новых запросов не порождают — иначе при недоступном сервере скролл превратится в поток сообщений.
    func test_loadNextPage_transportError_showsErrorAndStopsPagination() async throws {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true)),
            .failure(NetworkError.transport(URLError(.notConnectedToInternet))),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()
        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertEqual(sut.conversations.map(\.id), Array(1...30))
        XCTAssertEqual(conversationService.requests.count, 2)
    }

    /// Кейс: страница со сдвигом вернула переписку, которая уже есть в списке (список на сервере сдвинулся
    /// между запросами).
    /// Ожидание: дубликат не добавляется — в списке одинаковых `id` быть не должно.
    func test_loadNextPage_duplicateConversation_isNotAppended() async throws {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: [30, 31]), hasNext: false)),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(sut.conversations.map(\.id), Array(1...31))
    }

    /// Кейс: пока грузится список, началась новая загрузка первой страницы (pull-to-refresh поверх открытия).
    /// Ожидание: опоздавший ответ отброшен — на экране результат последней загрузки.
    func test_loadFirstPage_staleResponse_isDiscarded() async {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: [1]), hasNext: false)),
            .success(ConversationsPage(conversations: makeConversations(ids: [2]), hasNext: false)),
        ]
        conversationService.onRequest = { [unowned self] in
            conversationService.onRequest = nil
            await sut.loadFirstPage()
        }

        await sut.loadFirstPage()

        XCTAssertEqual(sut.conversations.map(\.id), [2])
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: pull-to-refresh во время подгрузки следующей страницы.
    /// Ожидание: опоздавшая страница не дописывается к обновлённому списку — на экране только результат обновления.
    func test_loadNextPage_staleResponse_isNotAppended() async throws {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: Array(31...40)), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: [100]), hasNext: false)),
        ]
        await sut.loadFirstPage()
        conversationService.onRequest = { [unowned self] in
            conversationService.onRequest = nil
            await sut.loadFirstPage()
        }

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(sut.conversations.map(\.id), [100])
    }

    // MARK: - Создание переписки

    /// Кейс: создана переписка, которой ещё нет в списке.
    /// Ожидание: она добавлена в начало списка.
    func test_didCreateConversation_addsToStart() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.groupStub], hasNext: false))]
        await sut.loadFirstPage()

        sut.didCreateConversation(.singleStub)

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id, Conversation.groupStub.id])
    }

    /// Кейс: созданная переписка добавлена в список локально, затем грузится следующая страница.
    /// Ожидание: сдвиг считается по числу полученных с сервера переписок — локальная вставка его не смещает,
    /// иначе одна переписка была бы пропущена.
    func test_didCreateConversation_doesNotShiftNextPageOffset() async throws {
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array(1...30)), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: [31]), hasNext: false)),
        ]
        await sut.loadFirstPage()
        sut.didCreateConversation(makeConversations(ids: [999])[0])

        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(conversationService.requests.last?.offset, 30)
        XCTAssertEqual(sut.conversations.map(\.id), [999] + Array(1...31))
    }

    /// Кейс: `createSingle` вернул переписку, которая уже есть в списке (повторный вызов для того же собеседника).
    /// Ожидание: список не меняется — дубликат не добавляется.
    func test_didCreateConversation_alreadyListed_doesNotDuplicate() async {
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        await sut.loadFirstPage()

        sut.didCreateConversation(.singleStub)

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id])
    }

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

        XCTAssertEqual(router.path.count, 1)
    }

    /// Кейс: выбран пункт «Личный диалог» в меню создания.
    /// Ожидание: модально открыт экран создания личного диалога.
    func test_didTapCreateSingleConversation_presentsSheet() {
        sut.didTapCreateSingleConversation()

        XCTAssertEqual(router.presentedSheet, .createSingleConversation)
    }

    // MARK: - Выход

    /// Кейс: нажатие на кнопку «Выйти».
    /// Ожидание: показан попап подтверждения, сам выход не запускается.
    func test_didTapLogout_presentsConfirmation() {
        sut.didTapLogout()

        XCTAssertTrue(sut.isLogoutConfirmationPresented)
        XCTAssertTrue(networkService.requestedEndpoints.isEmpty)
    }

    /// Кейс: нажатие на кнопку «Выйти», пока выход уже выполняется.
    /// Ожидание: повторный попап не показывается.
    func test_didTapLogout_whileLoggingOut_doesNotPresentConfirmation() async {
        let sut: ChatListViewModel = sut
        var isPresentedDuringLogout = true
        networkService.stubbedResult = .success(EmptyResponse())
        networkService.onRequest = {
            sut.didTapLogout()
            isPresentedDuringLogout = sut.isLogoutConfirmationPresented
        }

        await sut.logout()

        XCTAssertFalse(isPresentedDuringLogout)
    }

    /// Кейс: подтверждение в попапе.
    /// Ожидание: запрос выхода уходит на сервер, сессия завершается.
    func test_confirmLogout_startsLogout() async {
        networkService.stubbedResult = .success(EmptyResponse())
        sut.didTapLogout()

        sut.didTapConfirmLogout()
        await yieldUntil { !sessionService.isLoggedIn }

        XCTAssertFalse(sessionService.isLoggedIn)
    }

    /// Кейс: подтверждение в попапе, пока выход уже выполняется.
    /// Ожидание: повторный запрос не уходит — даже если дать ему время дойти до сети.
    func test_confirmLogout_whileLoggingOut_doesNotStartAgain() async {
        let sut: ChatListViewModel = sut
        let repeatedRequest = expectation(description: "Повторный запрос выхода")
        repeatedRequest.isInverted = true
        networkService.stubbedResult = .success(EmptyResponse())
        networkService.onRequest = { [unowned self] in
            networkService.onRequest = { repeatedRequest.fulfill() }
            sut.didTapConfirmLogout()
        }

        await sut.logout()
        await fulfillment(of: [repeatedRequest], timeout: 0.2)

        XCTAssertEqual(networkService.requestedEndpoints.count, 1)
    }

    /// Кейс: сервер успешно завершил сессию.
    /// Ожидание: сессия завершена, пользователь удалён из `UserDefaults`, ошибки нет.
    func test_logout_success_endsSession() async {
        networkService.stubbedResult = .success(EmptyResponse())

        await sut.logout()

        let stored = await userDefaultsService.currentUser()
        XCTAssertFalse(sessionService.isLoggedIn)
        XCTAssertNil(stored)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoggingOut)
    }

    /// Кейс: сервер ответил «не авторизован» — сессии на сервере уже нет.
    /// Ожидание: сессия завершена как при успехе, без сообщения об ошибке и без флага «истекла».
    func test_logout_unauthorized_endsSessionSilently() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.unauthorized))

        await sut.logout()

        XCTAssertFalse(sessionService.isLoggedIn)
        XCTAssertFalse(sessionService.isExpired)
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: транспортная ошибка при выходе.
    /// Ожидание: сессия сохраняется, показано сообщение об ошибке.
    func test_logout_transportError_showsErrorAndKeepsSession() async {
        networkService.stubbedResult = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        await sut.logout()

        XCTAssertTrue(sessionService.isLoggedIn)
        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
    }

    // MARK: - Выход во время загрузки

    /// Кейс: выход подтверждён, пока грузится первая страница; ответ на неё приходит уже после отмены.
    /// Ожидание: сессия завершается только после того, как загрузка закончилась; страница в БД не записана,
    /// ошибка не показана.
    func test_logout_duringFirstPage_cancelsLoadingBeforeEndingSession() async {
        let gate = Gate()
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        conversationService.onRequest = { await gate.wait() }
        networkService.stubbedResult = .success(EmptyResponse())
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.logout() }
        await yieldUntil { [unowned self] in !sut.isLoadingFirstPage }
        let isLoggedInBeforeLoadFinished = sessionService.isLoggedIn
        gate.open()
        await logout.value
        await load.value

        XCTAssertTrue(isLoggedInBeforeLoadFinished)
        XCTAssertFalse(sessionService.isLoggedIn)
        XCTAssertTrue(conversationStorage.savedPages.isEmpty)
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: выход подтверждён, пока грузится следующая страница; ответ на неё приходит уже после отмены.
    /// Ожидание: сессия завершается только после того, как подгрузка закончилась; в БД записана только первая страница.
    func test_logout_duringNextPage_cancelsLoadingBeforeEndingSession() async throws {
        let gate = Gate()
        conversationService.stubbedPages = [
            .success(ConversationsPage(conversations: makeConversations(ids: Array((1...30).reversed())), hasNext: true)),
            .success(ConversationsPage(conversations: makeConversations(ids: [0]), hasNext: false)),
        ]
        networkService.stubbedResult = .success(EmptyResponse())
        await sut.loadFirstPage()
        conversationService.onRequest = { await gate.wait() }
        sut.prefetchNextPageIfNeeded(currentConversation: try XCTUnwrap(sut.conversations.last))
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.logout() }
        await yieldUntil { [unowned self] in !sut.isLoadingNextPage }
        let isLoggedInBeforeLoadFinished = sessionService.isLoggedIn
        gate.open()
        await logout.value

        XCTAssertTrue(isLoggedInBeforeLoadFinished)
        XCTAssertFalse(sessionService.isLoggedIn)
        XCTAssertEqual(conversationStorage.savedPages.map(\.isFirstPage), [true])
    }

    /// Кейс: выход не удался из-за сети, пока грузится первая страница.
    /// Ожидание: загрузка не прерывается — после ответа страница показана и записана в БД.
    func test_logout_failure_doesNotCancelLoading() async {
        let gate = Gate()
        conversationService.stubbedPages = [.success(ConversationsPage(conversations: [.singleStub], hasNext: false))]
        conversationService.onRequest = { await gate.wait() }
        networkService.stubbedResult = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        let load = Task { await sut.loadFirstPage() }
        await yieldUntil { gate.isWaiting }

        await sut.logout()
        gate.open()
        await load.value

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.singleStub.id])
        XCTAssertEqual(conversationStorage.savedPages.count, 1)
    }

    // MARK: - Helpers

    /// Личные переписки с указанными идентификаторами — каждая со своим собеседником.
    /// - Parameter ids: идентификаторы переписок по возрастанию.
    private func makeConversations(ids: [Int]) -> [Conversation] {
        ids.map { id in
            Conversation(
                conversationId: id,
                type: .single,
                memberIds: [1, id + 1000],
                name: nil,
                avatar: nil,
                opponentUserId: id + 1000
            )
        }
    }

    /// Ждёт, пока завершится подгрузка следующей страницы, запущенная `prefetchNextPageIfNeeded`.
    private func waitUntilNextPageLoaded(file: StaticString = #filePath, line: UInt = #line) async {
        await yieldUntil(file: file, line: line) { [unowned self] in !sut.isLoadingNextPage }
    }
}

/// Флаг срабатывания `onChange` из `withObservationTracking`.
private final class ObservationFlag: @unchecked Sendable {
    var isSet = false
}
