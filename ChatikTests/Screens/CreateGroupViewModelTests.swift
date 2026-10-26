//
//  CreateGroupViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class CreateGroupViewModelTests: XCTestCase {
    private var groupService: GroupServiceMock!
    private var groupInfo: GroupInfoServiceMock!
    private var conversationList: ConversationListServiceMock!
    private var filesService: FilesServiceMock!
    private var imageFileStore: ImageFileStoreMock!
    private var notifications: InAppNotificationServiceMock!
    private var finished: [Conversation?] = []
    private var sut: CreateGroupViewModel!

    override func setUp() async throws {
        try await super.setUp()
        groupService = GroupServiceMock()
        groupInfo = GroupInfoServiceMock()
        conversationList = ConversationListServiceMock()
        filesService = FilesServiceMock()
        imageFileStore = ImageFileStoreMock()
        notifications = InAppNotificationServiceMock()
        finished = []
        sut = CreateGroupViewModel(
            groupService: groupService,
            groupInfo: groupInfo,
            conversationList: conversationList,
            filesService: filesService,
            imageFileStore: imageFileStore,
            notifications: notifications,
            router: CreateGroupRouter(onFinish: { [unowned self] in finished.append($0) }),
            isCameraAvailable: false
        )
    }

    /// Кейс: название пустое, из пробелов, нормальное, длиннее 128; описание длиннее 1024.
    /// Ожидание: «Создать» активна только при подходящих названии и описании.
    func test_createButton_enabledOnlyForValidInput() {
        XCTAssertFalse(sut.isCreateButtonEnabled)
        sut.name = "   "
        XCTAssertFalse(sut.isCreateButtonEnabled)
        sut.name = "Команда"
        XCTAssertTrue(sut.isCreateButtonEnabled)
        sut.groupDescription = String(repeating: "a", count: 1025)
        XCTAssertFalse(sut.isCreateButtonEnabled)
        XCTAssertEqual(sut.hint(for: sut.descriptionError), CreateGroupStrings.tooLong(maxLength: 1024))
        sut.groupDescription = ""
        sut.name = String(repeating: "a", count: 129)
        XCTAssertFalse(sut.isCreateButtonEnabled)
    }

    /// Кейс: «Создать» с названием и описанием в пробелах по краям, без аватара; сервер ответил группой.
    /// Ожидание: ушли обрезанные значения без аватара; состав и группа применены; экран завершён с группой.
    func test_create_sendsTrimmedValuesAndAppliesResult() async {
        let created = CreatedGroup(conversation: .groupStub, groupInfo: .make())
        groupService.stubbedCreate = .success(created)
        sut.name = "  Команда "
        sut.groupDescription = "  "

        sut.didTapCreate()

        await yieldUntil { [unowned self] in !finished.isEmpty }
        XCTAssertEqual(groupService.createRequests.first?.name, "Команда")
        XCTAssertNil(groupService.createRequests.first?.description ?? nil)
        XCTAssertNil(groupService.createRequests.first?.avatarFileId ?? nil)
        XCTAssertEqual(groupInfo.applied, [created.groupInfo])
        XCTAssertEqual(conversationList.applied, [created.conversation])
        XCTAssertEqual(finished, [created.conversation])
    }

    /// Кейс: «Создать» нажата дважды, пока запрос идёт.
    /// Ожидание: запрос один, кнопка неактивна до ответа.
    func test_create_ignoresRepeatedTapDuringRequest() async {
        let gate = Gate()
        groupService.actionGate = gate
        groupService.stubbedCreate = .success(CreatedGroup(conversation: .groupStub, groupInfo: .make()))
        sut.name = "Команда"

        sut.didTapCreate()
        sut.didTapCreate()
        await yieldUntil { gate.isWaiting }

        XCTAssertFalse(sut.isCreateButtonEnabled)
        XCTAssertEqual(groupService.createRequests.count, 1)
        gate.open()
        await yieldUntil { [unowned self] in !finished.isEmpty }
    }

    /// Кейс: сервер отклонил название (`1003`).
    /// Ожидание: текст про название группы, экран остаётся.
    func test_create_invalidName_showsGroupNameError() async {
        groupService.stubbedCreate = .failure(NetworkError.api(code: NetworkError.Code.invalidName))
        sut.name = "Команда"

        sut.didTapCreate()

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertEqual(notifications.shownErrors, [CreateGroupStrings.invalidName])
        XCTAssertTrue(finished.isEmpty)
        XCTAssertTrue(sut.isCreateButtonEnabled)
    }

    /// Кейс: выбрано изображение; пока оно загружается, «Создать» неактивна; после загрузки группа создаётся.
    /// Ожидание: во время загрузки кнопка неактивна; в запрос ушёл `fileId` загруженного файла.
    func test_avatar_uploadBlocksCreateAndIsSent() async {
        let gate = Gate()
        filesService.onUpload = { await gate.wait() }
        filesService.stubbedUpload = .success(.stub)
        groupService.stubbedCreate = .success(CreatedGroup(conversation: .groupStub, groupInfo: .make()))
        sut.name = "Команда"

        sut.didPickImage(.image(.stub()))
        await yieldUntil { gate.isWaiting }
        XCTAssertFalse(sut.isCreateButtonEnabled)
        XCTAssertTrue(sut.hasAvatar)
        gate.open()
        await yieldUntil { [unowned self] in sut.isCreateButtonEnabled }

        sut.didTapCreate()

        await yieldUntil { [unowned self] in !finished.isEmpty }
        XCTAssertEqual(groupService.createRequests.first?.avatarFileId ?? nil, RemoteFile.stub.fileId)
    }

    /// Кейс: аватар загружен, затем удалён.
    /// Ожидание: аватара нет, в запрос `fileId` не уходит.
    func test_avatar_removeClearsFile() async {
        filesService.stubbedUpload = .success(.stub)
        groupService.stubbedCreate = .success(CreatedGroup(conversation: .groupStub, groupInfo: .make()))
        sut.name = "Команда"
        sut.didPickImage(.image(.stub()))
        await yieldUntil { [unowned self] in sut.hasAvatar && sut.isCreateButtonEnabled }

        sut.didTapRemoveAvatar()
        sut.didTapCreate()

        XCTAssertFalse(sut.hasAvatar)
        await yieldUntil { [unowned self] in !finished.isEmpty }
        XCTAssertNil(groupService.createRequests.first?.avatarFileId ?? nil)
    }

    /// Кейс: загрузка аватара не удалась.
    /// Ожидание: ошибка показана, аватар вернулся к прежнему (его не было), кнопка снова активна.
    func test_avatar_uploadFailureRestoresPrevious() async {
        filesService.stubbedUpload = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        sut.name = "Команда"

        sut.didPickImage(.image(.stub()))

        await yieldUntil { [unowned self] in !notifications.shownErrors.isEmpty }
        XCTAssertFalse(sut.hasAvatar)
        XCTAssertTrue(sut.isCreateButtonEnabled)
    }

    /// Кейс: «Отмена» во время загрузки аватара.
    /// Ожидание: экран завершён без группы, ошибка отменённой загрузки не показывается.
    func test_cancel_cancelsUploadWithoutError() async {
        let gate = Gate()
        filesService.onUpload = { await gate.wait() }
        filesService.stubbedUpload = .failure(CancellationError())
        sut.didPickImage(.image(.stub()))
        await yieldUntil { gate.isWaiting }

        sut.didTapCancel()
        gate.open()

        await yieldTimes()
        XCTAssertEqual(finished, [nil])
        XCTAssertTrue(notifications.shownErrors.isEmpty)
    }

    /// Кейс: сервер отклонил файл аватара — `3003` (не изображение) или `3004` (не найден).
    /// Ожидание: текст про аватар, а не про файл.
    func test_create_avatarErrors_showAvatarText() async {
        let codes = [
            NetworkError.Code.fileNotImage,
            NetworkError.Code.fileNotFound,
        ]

        for code in codes {
            groupService.stubbedCreate = .failure(NetworkError.api(code: code))
            sut.name = "Команда"
            let shownBefore = notifications.shownErrors.count
            sut.didTapCreate()
            await yieldUntil { [unowned self] in notifications.shownErrors.count > shownBefore }
            XCTAssertEqual(notifications.shownErrors.last, CreateGroupStrings.avatarLoadFailed, "\(code)")
        }
    }

    /// Кейс: экран закрыт смахиванием во время загрузки аватара.
    /// Ожидание: загрузка отменена — ошибка не показывается, аватар не появляется.
    func test_didDisappear_cancelsUpload() async {
        let gate = Gate()
        filesService.onUpload = { await gate.wait() }
        filesService.stubbedUpload = .failure(CancellationError())
        sut.didPickImage(.image(.stub()))
        await yieldUntil { gate.isWaiting }

        sut.didDisappear()
        gate.open()

        await yieldTimes()
        XCTAssertTrue(notifications.shownErrors.isEmpty)
        XCTAssertFalse(sut.avatarUploader.isUploading)
    }
}
