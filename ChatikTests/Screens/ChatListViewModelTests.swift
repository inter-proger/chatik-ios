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
    private var router: ChatListRouter!
    private var sut: ChatListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        networkService = NetworkServiceMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService)
        await sessionService.restore()
        router = ChatListRouter()
        sut = ChatListViewModel(
            authService: AuthService(networkService: networkService),
            sessionService: sessionService,
            router: router
        )
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
