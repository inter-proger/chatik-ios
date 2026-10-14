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
    private var router: ChatListRouter!
    private var sut: ChatListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        conversationList = ConversationListServiceMock()
        userCache = UserCacheServiceMock()
        router = ChatListRouter()
        sut = makeSUT(now: { ServerTime.stub.date })
    }

    // MARK: - Список

    /// Кейс: в сервисе списка две переписки.
    /// Ожидание: строки показаны в порядке сервиса, с превью и временем.
    func test_conversations_mapsListInOrder() {
        conversationList.conversations = [.groupStub, .singleStub]

        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id, Conversation.singleStub.id])
        XCTAssertEqual(sut.conversations.first?.preview, "Привет!")
        XCTAssertFalse(sut.conversations.first?.time.isEmpty ?? true)
    }

    /// Кейс: список в сервисе изменился (переписка поднялась событием).
    /// Ожидание: экран узнаёт об изменении через Observation — строки перерисуются в новом порядке.
    func test_conversations_listChanged_notifiesObservers() {
        conversationList.conversations = [.singleStub, .groupStub]
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.conversations } onChange: { changed.isSet = true }

        conversationList.conversations = [.groupStub, .singleStub]

        XCTAssertTrue(changed.isSet)
        XCTAssertEqual(sut.conversations.map(\.id), [Conversation.groupStub.id, Conversation.singleStub.id])
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

        XCTAssertTrue(sut.isSyncing)
        XCTAssertFalse(sut.isEmpty)
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
        sut = makeSUT(now: { clock.date })
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
    func test_didSelectConversation_opensAndSelects() throws {
        conversationList.conversations = [.singleStub, .groupStub]

        sut.didSelectConversation(try XCTUnwrap(sut.conversations.last))

        XCTAssertEqual(router.path, [.conversation(.groupStub)])
        XCTAssertEqual(sut.selectedConversationId, Conversation.groupStub.id)
    }

    /// Кейс: открытую переписку закрыли — экран убран из стека навигации.
    /// Ожидание: выбор строки снят.
    func test_selectedConversationId_conversationClosed_isNil() throws {
        conversationList.conversations = [.singleStub]
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
    func test_conversations_opponentInCache_usesCachedName() {
        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))
        conversationList.conversations = [.singleStub]

        XCTAssertEqual(sut.conversations.first?.title, "Petr Sidorov")
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, false)
    }

    /// Кейс: собеседник догрузился в кэш уже после того, как строка показана с заглушкой.
    /// Ожидание: экран узнаёт об изменении через Observation, строка показывает имя.
    func test_conversations_opponentLoadedLater_updatesRow() {
        conversationList.conversations = [.singleStub]
        XCTAssertEqual(sut.conversations.first?.isTitlePlaceholder, true)
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.conversations } onChange: { changed.isSet = true }

        userCache.users[2] = .loaded(User(userId: 2, login: "petr", name: "Petr Sidorov", avatar: nil))

        XCTAssertTrue(changed.isSet)
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
    /// - Parameter now: текущее время.
    private func makeSUT(now: @escaping () -> Date) -> ChatListViewModel {
        ChatListViewModel(
            conversationList: conversationList,
            sessionService: sessionService,
            userCache: userCache,
            localizationService: LocalizationService(userDefaultsService: UserDefaultsServiceMock(), systemLanguage: .ru),
            router: router,
            now: now
        )
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
