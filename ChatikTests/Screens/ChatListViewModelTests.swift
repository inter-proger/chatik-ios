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
    private var router: ChatListRouter!
    private var sut: ChatListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        networkService = NetworkServiceMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService)
        await sessionService.restore()
        conversationService = ConversationServiceMock()
        router = ChatListRouter()
        sut = ChatListViewModel(
            authService: AuthService(networkService: networkService),
            sessionService: sessionService,
            conversationService: conversationService,
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
                opponentUser: User(userId: id + 1000, login: "user\(id)", name: "User \(id)", avatar: nil)
            )
        }
    }

    /// Ждёт, пока завершится подгрузка следующей страницы, запущенная `prefetchNextPageIfNeeded`.
    private func waitUntilNextPageLoaded(file: StaticString = #filePath, line: UInt = #line) async {
        await yieldUntil(file: file, line: line) { [unowned self] in !sut.isLoadingNextPage }
    }
}
