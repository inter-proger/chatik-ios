//
//  ProfileViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ProfileViewModelTests: XCTestCase {
    private let storedUser = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
    private var profileService: ProfileServiceMock!
    private var userDefaultsService: UserDefaultsServiceMock!
    private var sessionService: SessionService!
    private var sut: ProfileViewModel!

    override func setUp() async throws {
        try await super.setUp()
        profileService = ProfileServiceMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: storedUser)
        sessionService = SessionService(userDefaultsService: userDefaultsService)
        await sessionService.restore()
        sut = ProfileViewModel(profileService: profileService, sessionService: sessionService)
    }

    /// Кейс: сессия открыта, запрос профиля ещё не выполнялся.
    /// Ожидание: профиль для отображения собран из пользователя сессии — имя, логин, id как текст, без аватара.
    func test_profile_beforeLoad_reflectsSessionUser() {
        let expected = ProfileDisplayModel(name: "Ivan", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil)

        XCTAssertEqual(sut.profile, expected)
    }

    /// Кейс: сессии нет.
    /// Ожидание: профиля для отображения нет.
    func test_profile_withoutSession_isNil() async {
        await sessionService.end()

        XCTAssertNil(sut.profile)
    }

    /// Кейс: сервер вернул обновлённый профиль (с аватаром).
    /// Ожидание: сессия и `UserDefaults` обновлены, на экране полноразмерный URL аватара и URL уменьшенной копии, ошибки нет.
    func test_loadProfile_success_updatesSessionAndProfile() async {
        let updated = User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: .stub)
        profileService.stubbedProfile = .success(updated)

        await sut.loadProfile()

        let stored = await userDefaultsService.currentUser()
        XCTAssertEqual(sessionService.currentUser, updated)
        XCTAssertEqual(stored, updated)
        XCTAssertEqual(sut.profile?.name, "Ivan Petrov")
        XCTAssertEqual(sut.profile?.avatarURL, RemoteFile.stub.url)
        XCTAssertEqual(sut.profile?.avatarThumbnailURL, RemoteFile.stub.smallURL)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    /// Кейс: транспортная ошибка при запросе профиля.
    /// Ожидание: показано сообщение об ошибке, пользователь сессии не изменён и по-прежнему отображается.
    func test_loadProfile_transportError_showsErrorAndKeepsSessionUser() async {
        profileService.stubbedProfile = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        await sut.loadProfile()

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertEqual(sessionService.currentUser, storedUser)
        XCTAssertEqual(sut.profile?.login, "ivan")
    }

    /// Кейс: во время запроса профиля.
    /// Ожидание: флаг `isLoading` поднят на время запроса и сброшен после.
    func test_loadProfile_setsLoadingDuringRequest() async {
        let sut: ProfileViewModel = sut
        var wasLoading = false
        profileService.stubbedProfile = .success(storedUser)
        profileService.onRequest = { wasLoading = sut.isLoading }

        await sut.loadProfile()

        XCTAssertTrue(wasLoading)
        XCTAssertFalse(sut.isLoading)
    }

    /// Кейс: повторный вызов `loadProfile` внутри первого запроса — пока он гарантированно выполняется.
    /// Ожидание: второй запрос не отправляется.
    func test_loadProfile_whileLoading_ignoresRepeatedCall() async {
        let sut: ProfileViewModel = sut
        profileService.stubbedProfile = .success(storedUser)
        profileService.onRequest = { await sut.loadProfile() }

        await sut.loadProfile()

        XCTAssertEqual(profileService.fetchProfileCallCount, 1)
    }
}
