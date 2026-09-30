//
//  CreateSingleConversationViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class CreateSingleConversationViewModelTests: XCTestCase {
    private var usersService: UsersServiceMock!
    private var conversationService: ConversationServiceMock!
    private var sessionService: SessionService!
    /// Результаты завершения экрана: `Conversation` — созданная переписка, `nil` — отмена.
    private var finishResults: [Conversation?]!
    private var sut: CreateSingleConversationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        usersService = UsersServiceMock()
        conversationService = ConversationServiceMock()
        sessionService = SessionService(userDefaultsService: UserDefaultsServiceMock(currentUser: .stub))
        await sessionService.restore()
        finishResults = []
        sut = makeSUT(searchDebounce: .zero)
    }

    // MARK: - Первая страница

    /// Кейс: открытие экрана, сервер вернул страницу, в которой есть и текущий пользователь.
    /// Ожидание: в списке все, кроме текущего пользователя; запрос — первая страница заданного размера без фильтра.
    func test_loadFirstPage_showsUsersExceptCurrent() async {
        usersService.stubbedPages = [.success(makePage(ids: [1, 2, 3]))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.users.map(\.id), [2, 3])
        XCTAssertEqual(usersService.requests.first?.maxId, nil)
        XCTAssertEqual(usersService.requests.first?.count, CreateSingleConversationViewModel.pageSize)
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: первая страница грузится.
    /// Ожидание: флаг загрузки первой страницы поднят, список считается не пустым.
    func test_loadFirstPage_whileLoading_setsLoadingFlag() async {
        usersService.stubbedPages = [.success(makePage(ids: [2]))]
        var isLoadingDuringRequest = false
        var isEmptyDuringRequest = true
        usersService.onRequest = { [unowned self] in
            isLoadingDuringRequest = sut.isLoadingFirstPage
            isEmptyDuringRequest = sut.isEmpty
        }

        await sut.loadFirstPage()

        XCTAssertTrue(isLoadingDuringRequest)
        XCTAssertFalse(isEmptyDuringRequest)
    }

    /// Кейс: сервер вернул пустую страницу.
    /// Ожидание: список пуст — экран показывает сообщение об отсутствии пользователей.
    func test_loadFirstPage_emptyPage_isEmpty() async {
        usersService.stubbedPages = [.success(makePage(ids: []))]

        await sut.loadFirstPage()

        XCTAssertTrue(sut.isEmpty)
    }

    /// Кейс: транспортная ошибка при загрузке первой страницы.
    /// Ожидание: показано сообщение об ошибке.
    func test_loadFirstPage_transportError_showsError() async {
        usersService.stubbedPages = [.failure(NetworkError.transport(URLError(.notConnectedToInternet)))]

        await sut.loadFirstPage()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: список показан, затем загрузка первой страницы по новому поисковому запросу завершилась ошибкой.
    /// Ожидание: прежний список остаётся на экране, но подгрузка следующей страницы к нему больше не идёт —
    /// иначе к результатам старого запроса дописались бы результаты нового.
    func test_loadFirstPage_error_stopsPagination() async throws {
        usersService.stubbedPages = [
            .success(makePage(ids: Array(2...31))),
            .failure(NetworkError.transport(URLError(.notConnectedToInternet))),
        ]
        await sut.loadFirstPage()
        sut.searchText = "new"
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.last))

        XCTAssertEqual(sut.users.map(\.id), Array(2...31))
        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertEqual(usersService.requests.count, 2)
    }

    /// Кейс: повторная загрузка (pull-to-refresh) после того, как список уже был показан.
    /// Ожидание: список заменяется новой страницей, а не дописывается.
    func test_loadFirstPage_again_replacesUsers() async {
        usersService.stubbedPages = [
            .success(makePage(ids: [2, 3])),
            .success(makePage(ids: [4])),
        ]

        await sut.loadFirstPage()
        await sut.loadFirstPage()

        XCTAssertEqual(sut.users.map(\.id), [4])
    }

    /// Кейс: пока грузится список по старому запросу, пользователь изменил запрос и началась новая загрузка.
    /// Ожидание: опоздавший ответ по старому запросу отброшен — в списке результат нового запроса.
    func test_loadFirstPage_staleResponse_isDiscarded() async {
        usersService.stubbedPages = [
            .success(makePage(ids: [2])),
            .success(makePage(ids: [3])),
        ]
        usersService.onRequest = { [unowned self] in
            usersService.onRequest = nil
            sut.searchText = "new"
            await sut.loadFirstPage()
        }

        await sut.loadFirstPage()

        XCTAssertEqual(sut.users.map(\.id), [3])
        XCTAssertEqual(usersService.requests.last?.query, "new")
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    // MARK: - Следующие страницы

    /// Кейс: первая страница полная, на экране появился один из последних пользователей.
    /// Ожидание: следующая страница запрошена с `maxId` из предыдущего ответа и дописана к списку.
    func test_prefetchNextPage_nearEnd_appendsNextPage() async throws {
        let firstPage = makePage(ids: Array(2...31))
        usersService.stubbedPages = [
            .success(firstPage),
            .success(makePage(ids: [32])),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(usersService.requests.last?.maxId, firstPage.nextMaxId)
        XCTAssertEqual(sut.users.map(\.id), Array(2...32))
    }

    /// Кейс: первая страница полная, на экране пользователь из начала списка.
    /// Ожидание: следующая страница не запрашивается.
    func test_prefetchNextPage_farFromEnd_doesNotLoad() async throws {
        usersService.stubbedPages = [.success(makePage(ids: Array(2...31)))]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.first))

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertEqual(usersService.requests.count, 1)
    }

    /// Кейс: сервер ответил `hasNext: false` — эта страница последняя.
    /// Ожидание: при показе последнего пользователя следующая страница не запрашивается.
    func test_prefetchNextPage_lastPage_doesNotLoad() async throws {
        usersService.stubbedPages = [.success(makePage(ids: [2, 3], hasNext: false))]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.last))

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertEqual(usersService.requests.count, 1)
    }

    /// Кейс: страница короче запрошенной (часть отфильтрована как текущий пользователь), но сервер сообщил `hasNext: true`.
    /// Ожидание: следующая страница запрашивается — признак следующей страницы берётся из ответа, а не из числа строк.
    func test_prefetchNextPage_shortPageWithHasNext_loadsNextPage() async throws {
        usersService.stubbedPages = [
            .success(makePage(ids: Array(1...30))),
            .success(makePage(ids: [31], hasNext: false)),
        ]
        await sut.loadFirstPage()

        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(usersService.requests.count, 2)
        XCTAssertEqual(sut.users.last?.id, 31)
    }

    // MARK: - Поиск

    /// Кейс: в поле поиска введён текст.
    /// Ожидание: после паузы запрос уходит с этим текстом.
    func test_searchTextDidChange_loadsWithQuery() async {
        usersService.stubbedPages = [.success(makePage(ids: [2]))]
        sut.searchText = "iv"

        await sut.searchTextDidChange()

        XCTAssertEqual(usersService.requests.map(\.query), ["iv"])
        XCTAssertEqual(sut.users.map(\.id), [2])
    }

    /// Кейс: ввод продолжился во время паузы — предыдущий запуск отменён.
    /// Ожидание: по отменённому запуску запрос не уходит.
    func test_searchTextDidChange_cancelledDuringDebounce_doesNotLoad() async {
        sut = makeSUT(searchDebounce: .seconds(10))
        sut.searchText = "iv"

        let task = Task { await sut.searchTextDidChange() }
        task.cancel()
        await task.value

        XCTAssertTrue(usersService.requests.isEmpty)
    }

    /// Кейс: в поле поиска введён новый текст, но пауза перед поиском ещё идёт — а на экране показан один из последних
    /// пользователей прежней выдачи.
    /// Ожидание: следующая страница запрошена под запрос, по которому загружен список, — иначе к нему дописались бы
    /// результаты другого поиска с курсором от прежнего.
    func test_prefetchNextPage_duringSearchDebounce_usesListedQuery() async throws {
        usersService.stubbedPages = [
            .success(makePage(ids: Array(2...31))),
            .success(makePage(ids: [32], hasNext: false)),
        ]
        sut.searchText = "iv"
        await sut.loadFirstPage()

        sut.searchText = "ivan"
        sut.prefetchNextPageIfNeeded(currentUser: try XCTUnwrap(sut.users.last))
        await waitUntilNextPageLoaded()

        XCTAssertEqual(usersService.requests.map(\.query), ["iv", "iv"])
        XCTAssertEqual(sut.users.last?.id, 32)
    }

    /// Кейс: выбранный пользователь есть в результатах нового поиска.
    /// Ожидание: выбор сохраняется.
    func test_search_selectedUserListed_keepsSelection() async throws {
        usersService.stubbedPages = [
            .success(makePage(ids: [2, 3])),
            .success(makePage(ids: [3])),
        ]
        await sut.loadFirstPage()
        sut.didSelect(try XCTUnwrap(sut.users.last))

        sut.searchText = "p"
        await sut.searchTextDidChange()

        XCTAssertEqual(sut.selectedUserId, 3)
    }

    /// Кейс: выбранного пользователя нет в результатах нового поиска.
    /// Ожидание: выбор сброшен, кнопка «Создать» неактивна.
    func test_search_selectedUserNotListed_resetsSelection() async throws {
        usersService.stubbedPages = [
            .success(makePage(ids: [2, 3])),
            .success(makePage(ids: [3])),
        ]
        await sut.loadFirstPage()
        sut.didSelect(try XCTUnwrap(sut.users.first))

        sut.searchText = "p"
        await sut.searchTextDidChange()

        XCTAssertNil(sut.selectedUserId)
        XCTAssertFalse(sut.isCreateButtonEnabled)
    }

    // MARK: - Выбор и создание

    /// Кейс: собеседник не выбран.
    /// Ожидание: кнопка «Создать» неактивна.
    func test_isCreateButtonEnabled_withoutSelection_isFalse() {
        XCTAssertFalse(sut.isCreateButtonEnabled)
    }

    /// Кейс: выбран пользователь из списка.
    /// Ожидание: он становится собеседником, кнопка «Создать» активна.
    func test_didSelect_enablesCreateButton() async throws {
        usersService.stubbedPages = [.success(makePage(ids: [2, 3]))]
        await sut.loadFirstPage()

        sut.didSelect(try XCTUnwrap(sut.users.last))

        XCTAssertEqual(sut.selectedUserId, 3)
        XCTAssertTrue(sut.isCreateButtonEnabled)
    }

    /// Кейс: сервер создал переписку с выбранным пользователем.
    /// Ожидание: запрос ушёл с идентификатором собеседника, переписка передана наружу — экран закрывается.
    func test_createConversation_success_reportsConversation() async throws {
        usersService.stubbedPages = [.success(makePage(ids: [2]))]
        conversationService.stubbedConversation = .success(.singleStub)
        await sut.loadFirstPage()
        sut.didSelect(try XCTUnwrap(sut.users.first))

        await sut.createConversation()

        XCTAssertEqual(conversationService.createSingleUserIds, [2])
        XCTAssertEqual(finishResults, [.singleStub])
        XCTAssertFalse(sut.isCreating)
        XCTAssertNil(sut.errorMessage)
    }

    /// Кейс: переписка создаётся.
    /// Ожидание: кнопка «Создать» неактивна, выбрать другого собеседника нельзя.
    func test_createConversation_whileCreating_disablesCreateAndSelection() async throws {
        usersService.stubbedPages = [.success(makePage(ids: [2, 3]))]
        conversationService.stubbedConversation = .success(.singleStub)
        await sut.loadFirstPage()
        let users = sut.users
        sut.didSelect(try XCTUnwrap(users.first))
        var isEnabledDuringRequest = true
        conversationService.onRequest = { [unowned self] in
            isEnabledDuringRequest = sut.isCreateButtonEnabled
            sut.didSelect(users[1])
        }

        await sut.createConversation()

        XCTAssertFalse(isEnabledDuringRequest)
        XCTAssertEqual(sut.selectedUserId, 2)
    }

    /// Кейс: сервер ответил ошибкой на создание переписки.
    /// Ожидание: показано сообщение, экран не закрывается, выбор сохраняется.
    func test_createConversation_apiError_showsError() async throws {
        usersService.stubbedPages = [.success(makePage(ids: [2]))]
        conversationService.stubbedConversation = .failure(NetworkError.api(code: NetworkError.Code.userNotFound))
        await sut.loadFirstPage()
        sut.didSelect(try XCTUnwrap(sut.users.first))

        await sut.createConversation()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorUserNotFound)
        XCTAssertTrue(finishResults.isEmpty)
        XCTAssertEqual(sut.selectedUserId, 2)
    }

    /// Кейс: нажатие «Создать», когда собеседник не выбран.
    /// Ожидание: запрос не уходит, экран не завершается.
    func test_didTapCreate_withoutSelection_doesNothing() async {
        sut.didTapCreate()
        await Task.yield()

        XCTAssertTrue(conversationService.createSingleUserIds.isEmpty)
        XCTAssertTrue(finishResults.isEmpty)
    }

    /// Кейс: нажатие «Отмена».
    /// Ожидание: экран завершается без переписки.
    func test_didTapCancel_finishesWithoutConversation() {
        sut.didTapCancel()

        XCTAssertEqual(finishResults.count, 1)
        XCTAssertNil(finishResults.first ?? nil)
    }

    // MARK: - Helpers

    /// Создаёт тестируемую ViewModel над моками; результаты завершения экрана складываются в `finishResults`.
    /// - Parameter searchDebounce: пауза поиска.
    private func makeSUT(searchDebounce: Duration) -> CreateSingleConversationViewModel {
        CreateSingleConversationViewModel(
            usersService: usersService,
            conversationService: conversationService,
            sessionService: sessionService,
            router: CreateSingleConversationRouter(onFinish: { [unowned self] in finishResults.append($0) }),
            searchDebounce: searchDebounce
        )
    }

    /// Страница пользователей с указанными идентификаторами; `nextMaxId` — последний из них.
    /// - Parameters:
    ///   - ids: идентификаторы пользователей по возрастанию.
    ///   - hasNext: есть ли следующая страница; по умолчанию есть — пагинация в тестах продолжается.
    private func makePage(ids: [Int], hasNext: Bool = true) -> UsersPage {
        UsersPage(
            users: ids.map { User(userId: $0, login: "user\($0)", name: "User \($0)", avatar: nil) },
            nextMaxId: ids.last,
            hasNext: hasNext
        )
    }

    /// Ждёт, пока завершится подгрузка следующей страницы, запущенная `prefetchNextPageIfNeeded`.
    private func waitUntilNextPageLoaded(file: StaticString = #filePath, line: UInt = #line) async {
        await yieldUntil(file: file, line: line) { [unowned self] in !sut.isLoadingNextPage }
    }
}
