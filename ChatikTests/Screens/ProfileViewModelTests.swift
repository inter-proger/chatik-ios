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
    private var filesService: FilesServiceMock!
    private var imageEncoder: ImageEncoderMock!
    private var userDefaultsService: UserDefaultsServiceMock!
    private var sessionService: SessionService!
    private var sut: ProfileViewModel!

    override func setUp() async throws {
        try await super.setUp()
        profileService = ProfileServiceMock()
        filesService = FilesServiceMock()
        imageEncoder = ImageEncoderMock()
        userDefaultsService = UserDefaultsServiceMock(currentUser: storedUser)
        sessionService = SessionService(userDefaultsService: userDefaultsService)
        await sessionService.restore()
        sut = makeSUT(isCameraAvailable: true)
    }

    private func makeSUT(isCameraAvailable: Bool) -> ProfileViewModel {
        ProfileViewModel(
            profileService: profileService,
            filesService: filesService,
            imageEncoder: imageEncoder,
            sessionService: sessionService,
            isCameraAvailable: isCameraAvailable
        )
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

    // MARK: - Аватар

    /// Кейс: на устройстве есть камера.
    /// Ожидание: предлагаются оба источника — галерея и камера.
    func test_avatarSources_withCamera_offersGalleryAndCamera() {
        XCTAssertEqual(sut.avatarSources, [.gallery, .camera])
    }

    /// Кейс: камеры нет (симулятор, iPad без камеры).
    /// Ожидание: предлагается только галерея.
    func test_avatarSources_withoutCamera_offersGalleryOnly() {
        let sut = makeSUT(isCameraAvailable: false)

        XCTAssertEqual(sut.avatarSources, [.gallery])
    }

    /// Кейс: аватара нет, нажатие на аватар.
    /// Ожидание: показан выбор источника.
    func test_didTapAvatar_withoutAvatar_presentsSources() {
        sut.didTapAvatar()

        XCTAssertTrue(sut.isAvatarSourcesPresented)
    }

    /// Кейс: аватар установлен, нажатие на аватар.
    /// Ожидание: выбор источника не показывается.
    func test_didTapAvatar_withAvatar_doesNothing() async {
        await sessionService.update(user: User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub))

        sut.didTapAvatar()

        XCTAssertFalse(sut.isAvatarSourcesPresented)
    }

    /// Кейс: выбор источника в диалоге.
    /// Ожидание: открыт пикер этого источника.
    func test_didSelectAvatarSource_presentsPicker() {
        sut.didSelectAvatarSource(.camera)

        XCTAssertEqual(sut.presentedAvatarSource, .camera)
    }

    /// Кейс: выбранный файл из галереи не удалось прочитать.
    /// Ожидание: пикер закрыт, показано сообщение об ошибке.
    func test_didFailToPickImage_closesPickerAndShowsError() {
        sut.didSelectAvatarSource(.gallery)

        sut.didFailToPickImage()

        XCTAssertNil(sut.presentedAvatarSource)
        XCTAssertEqual(sut.errorMessage, ProfileStrings.avatarLoadFailed)
    }

    /// Кейс: изображение выбрано, загрузка и назначение аватара прошли успешно.
    /// Ожидание: на сервер ушёл закодированный JPEG под именем `avatar.jpg`, аватар назначен по `fileId`
    /// загруженного файла, сессия обновлена, ошибки нет.
    func test_uploadAvatar_success_uploadsEncodedImageAndUpdatesSession() async {
        let encoded = Data("ENCODED".utf8)
        let updated = User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub)
        imageEncoder.stubbedResult = .success(encoded)
        filesService.stubbedUpload = .success(.stub)
        profileService.stubbedProfile = .success(updated)

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertEqual(filesService.uploads.count, 1)
        XCTAssertEqual(filesService.uploads.first?.data, encoded)
        XCTAssertEqual(filesService.uploads.first?.filename, "avatar.jpg")
        XCTAssertEqual(filesService.uploads.first?.type, .jpeg)
        XCTAssertEqual(profileService.setAvatarFileIds, [RemoteFile.stub.fileId])
        XCTAssertEqual(sessionService.currentUser, updated)
        XCTAssertEqual(sut.profile?.avatarURL, RemoteFile.stub.url)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isUploadingAvatar)
    }

    /// Кейс: изображение не удалось декодировать / закодировать.
    /// Ожидание: запрос в сеть не уходит, показано сообщение про выбранное изображение (а не общее про сеть).
    func test_uploadAvatar_encodingFails_showsImageErrorWithoutUpload() async {
        let errors: [ImageEncoderError] = [
            .decodingFailed,
            .encodingFailed,
        ]

        for error in errors {
            imageEncoder.stubbedResult = .failure(error)
            sut.errorMessage = nil

            await sut.uploadAvatar(.file(Data()))

            XCTAssertTrue(filesService.uploads.isEmpty, "\(error)")
            XCTAssertEqual(sut.errorMessage, ProfileStrings.avatarLoadFailed, "\(error)")
        }
    }

    /// Кейс: сервер отклонил файл как слишком большой.
    /// Ожидание: аватар не назначается, показано сообщение о размере файла, пользователь сессии не изменён.
    func test_uploadAvatar_uploadFails_showsErrorAndKeepsUser() async {
        filesService.stubbedUpload = .failure(NetworkError.api(code: NetworkError.Code.fileTooLarge))

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertTrue(profileService.setAvatarFileIds.isEmpty)
        XCTAssertEqual(sut.errorMessage, CommonStrings.errorFileTooLarge)
        XCTAssertEqual(sessionService.currentUser, storedUser)
    }

    /// Кейс: файл загружен, но назначение аватара завершилось транспортной ошибкой.
    /// Ожидание: показано сообщение об отсутствии соединения, пользователь сессии не изменён.
    func test_uploadAvatar_setAvatarFails_showsErrorAndKeepsUser() async {
        filesService.stubbedUpload = .success(.stub)
        profileService.stubbedProfile = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertEqual(sut.errorMessage, CommonStrings.errorNoConnection)
        XCTAssertEqual(sessionService.currentUser, storedUser)
    }

    /// Кейс: во время загрузки аватара.
    /// Ожидание: флаг `isUploadingAvatar` поднят на время запроса, нажатие на аватар в это время игнорируется.
    func test_uploadAvatar_setsUploadingAndBlocksTap() async {
        let sut: ProfileViewModel = sut
        var wasUploading = false
        var presentedDuringUpload = false
        filesService.stubbedUpload = .success(.stub)
        profileService.stubbedProfile = .success(storedUser)
        profileService.onRequest = {
            wasUploading = sut.isUploadingAvatar
            sut.didTapAvatar()
            presentedDuringUpload = sut.isAvatarSourcesPresented
        }

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertTrue(wasUploading)
        XCTAssertFalse(presentedDuringUpload)
        XCTAssertFalse(sut.isUploadingAvatar)
    }

    /// Кейс: файл отправлен (делегат ничего не сообщил), аватар назначается; затем установка завершена.
    /// Ожидание: во время отправки прогресс 0; на время назначения аватара — 1, даже без колбэков делегата;
    /// после завершения — `nil`.
    func test_uploadAvatar_progressFollowsUploadStages() async {
        let sut: ProfileViewModel = sut
        var progressDuringUpload: Double?
        var progressDuringSetAvatar: Double?
        filesService.stubbedUpload = .success(.stub)
        filesService.onUpload = { progressDuringUpload = sut.avatarUploadProgress }
        profileService.stubbedProfile = .success(storedUser)
        profileService.onRequest = { progressDuringSetAvatar = sut.avatarUploadProgress }

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertEqual(progressDuringUpload, 0)
        XCTAssertEqual(progressDuringSetAvatar, 1)
        XCTAssertNil(sut.avatarUploadProgress)
    }

    /// Кейс: сервис файлов сообщает прогресс через `onProgress` (колбэк не на main, доставляется отдельной задачей).
    /// Ожидание: значение доходит до `avatarUploadProgress`, пока отправка ещё идёт.
    func test_uploadAvatar_forwardsProgressCallbackToState() async {
        let sut: ProfileViewModel = sut
        var progressDuringUpload: Double?
        filesService.stubbedUpload = .success(.stub)
        filesService.stubbedUploadProgress = [0.5]
        filesService.onUpload = {
            // Колбэк ставит обновление в очередь main actor отдельной задачей — уступаем ей, оставаясь внутри отправки.
            await Self.yieldUntil { sut.avatarUploadProgress == 0.5 }
            progressDuringUpload = sut.avatarUploadProgress
        }
        profileService.stubbedProfile = .success(storedUser)

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertEqual(progressDuringUpload, 0.5)
    }

    /// Кейс: значения прогресса приходят не по порядку (доставка на main из фоновых задач не упорядочена).
    /// Ожидание: прогресс только растёт — более раннее значение не откатывает его назад.
    func test_didSendAvatarBytes_isMonotonic() async {
        let sut: ProfileViewModel = sut
        var progressDuringUpload: Double?
        filesService.stubbedUpload = .success(.stub)
        filesService.onUpload = {
            sut.didSendAvatarBytes(0.25)
            sut.didSendAvatarBytes(0.75)
            sut.didSendAvatarBytes(0.5)
            progressDuringUpload = sut.avatarUploadProgress
        }
        profileService.stubbedProfile = .success(storedUser)

        await sut.uploadAvatar(.image(.stub()))

        XCTAssertEqual(progressDuringUpload, 0.75)
    }

    /// Кейс: колбэк прогресса пришёл, когда загрузка не идёт (поздняя доставка после завершения).
    /// Ожидание: игнорируется — прогресс остаётся `nil`, кольцо загрузки не появляется.
    func test_didSendAvatarBytes_outsideUpload_isIgnored() {
        sut.didSendAvatarBytes(0.5)

        XCTAssertNil(sut.avatarUploadProgress)
    }

    /// Кейс: выбрано изображение из пикера.
    /// Ожидание: пикер закрыт сразу, загрузка запущена — дожидаемся её через хук сервиса.
    func test_didPickImage_closesPickerAndStartsUpload() async {
        filesService.stubbedUpload = .success(.stub)
        profileService.stubbedProfile = .success(storedUser)
        let requestStarted = expectation(description: "setAvatar called")
        profileService.onRequest = { requestStarted.fulfill() }
        sut.didSelectAvatarSource(.gallery)

        sut.didPickImage(.image(.stub()))

        XCTAssertNil(sut.presentedAvatarSource)
        await fulfillment(of: [requestStarted], timeout: 1)
        XCTAssertEqual(filesService.uploads.count, 1)
    }

    // MARK: - Helpers

    /// Уступает main actor уже поставленным в очередь задачам, пока `condition` не выполнится (не дольше 100 итераций).
    /// Нужен там, где обновление приходит через `Task { @MainActor in }` из не-main колбэка.
    private static func yieldUntil(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 100 {
            await Task.yield()
            attempts += 1
        }
    }
}
