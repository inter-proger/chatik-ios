//
//  ChatListViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatListViewModelTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var userDefaultsService: UserDefaultsServiceMock!
    private var sessionService: SessionService!
    private var sut: ChatListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        networkService = NetworkServiceMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: AuthUser(userId: 1, name: "Ivan"))
        sessionService = SessionService(userDefaultsService: userDefaultsService)
        await sessionService.restore()
        sut = ChatListViewModel(
            authService: AuthService(networkService: networkService),
            sessionService: sessionService,
            router: ChatListRouter()
        )
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
}
