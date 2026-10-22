//
//  DebugLoginServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class DebugLoginServiceTests: XCTestCase {
    private let previousUser = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
    private let user = User(userId: 2, login: "anna", name: "Anna", avatar: nil)
    private let credentials = DebugLoginCredentials(login: "anna", password: "Password1")
    private var authService: AuthServiceMock!
    private var conversationList: ConversationListServiceMock!
    private var messageSendQueue: MessageSendQueueMock!
    private var realtimeService: RealtimeServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        authService = AuthServiceMock()
        conversationList = ConversationListServiceMock()
        messageSendQueue = MessageSendQueueMock()
        realtimeService = RealtimeServiceMock()
    }

    /// Создаёт сервис над восстановленной сессией с заданным сохранённым пользователем.
    /// - Parameter storedUser: пользователь, залогиненный до запуска.
    private func makeSUT(storedUser: User?) async -> (DebugLoginService, SessionService) {
        let session = SessionService(
            userDefaultsService: UserDefaultsServiceMock(currentUser: storedUser),
            localStorageCleaner: LocalStorageCleanerMock()
        )
        await session.restore()
        let sessionWork = SessionWorkLauncher(
            conversationList: conversationList,
            messageNotifications: MessageNotificationServiceMock(),
            memberReads: MemberReadServiceMock(),
            messageDelivery: messageSendQueue,
            realtimeService: realtimeService
        )
        let sut = DebugLoginService(authService: authService, sessionService: session, sessionWork: sessionWork)
        return (sut, session)
    }

    /// Кейс: на устройстве залогинен другой пользователь, вход успешен.
    /// Ожидание: сначала выход, затем вход с переданными данными; сессия открыта новым пользователем до начала
    /// работы с сервером.
    func test_login_loggedIn_logsOutThenLogsInAndStartsWork() async throws {
        authService.stubbedUser = .success(user)
        let (sut, session) = await makeSUT(storedUser: previousUser)
        var userAtWorkStart: User?
        conversationList.onStart = { userAtWorkStart = session.currentUser }

        try await sut.login(credentials)

        XCTAssertEqual(authService.calls, ["logout", "login(anna/Password1)"])
        XCTAssertEqual(userAtWorkStart, user)
        XCTAssertEqual(session.currentUser, user)
        XCTAssertEqual(realtimeService.calls, ["start"])
    }

    /// Кейс: на устройстве залогинен тот же пользователь, которым входим.
    /// Ожидание: выход всё равно выполняется перед входом.
    func test_login_sameUserLoggedIn_logsOutAnyway() async throws {
        authService.stubbedUser = .success(user)
        let (sut, _) = await makeSUT(storedUser: user)

        try await sut.login(credentials)

        XCTAssertEqual(authService.calls, ["logout", "login(anna/Password1)"])
    }

    /// Кейс: на устройстве никто не залогинен.
    /// Ожидание: выхода нет, только вход; работа с сервером начата.
    func test_login_notLoggedIn_skipsLogout() async throws {
        authService.stubbedUser = .success(user)
        let (sut, session) = await makeSUT(storedUser: nil)

        try await sut.login(credentials)

        XCTAssertEqual(authService.calls, ["login(anna/Password1)"])
        XCTAssertEqual(session.currentUser, user)
        XCTAssertEqual(realtimeService.calls, ["start"])
    }

    /// Кейс: вход вернул ошибку.
    /// Ожидание: ошибка проброшена; сессия не открыта, работа с сервером не начата.
    func test_login_failure_throwsWithoutStartingSession() async {
        authService.stubbedUser = .failure(NetworkError.api(code: NetworkError.Code.invalidPassword))
        let (sut, session) = await makeSUT(storedUser: nil)

        do {
            try await sut.login(credentials)
            XCTFail("Ожидалась ошибка входа")
        } catch NetworkError.api(let code) {
            XCTAssertEqual(code, NetworkError.Code.invalidPassword)
        } catch {
            XCTFail("Неожиданная ошибка: \(error)")
        }

        XCTAssertNil(session.currentUser)
        XCTAssertEqual(realtimeService.calls, [])
        XCTAssertEqual(messageSendQueue.resumeCallCount, 0)
    }
}
