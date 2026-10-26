//
//  CreateGroupViewModel.swift
//  Chatik
//

import Foundation
import Observation
import UIKit

/// Экран создания группы: аватар, название и описание (`docs/group-chats.md`, решение 10).
///
/// **Аватар загружается сразу после выбора** — создание остаётся одним быстрым запросом, а прогресс виден на аватаре.
/// Пока идёт загрузка, показывается локальное превью; «Создать» неактивна. Новый выбор отменяет идущую загрузку,
/// удаление сбрасывает загруженный файл, ошибка возвращает прежний аватар. Закрытие экрана отменяет загрузку.
///
/// **Создание не идемпотентно**: кнопка неактивна всё время запроса, повторные нажатия игнорируются.
@MainActor
@Observable
final class CreateGroupViewModel {
    /// Название в поле ввода.
    var name = ""
    /// Описание в поле ввода.
    var groupDescription = ""
    /// Показан ли выбор источника аватара.
    var isAvatarSourcesPresented = false
    /// Источник, чей пикер на экране; `nil` — пикер скрыт.
    var presentedAvatarSource: AvatarSource?
    /// `true`, пока идёт запрос создания.
    private(set) var isCreating = false
    /// Показанный аватар: локальное превью выбранного изображения. `nil` — аватара нет.
    private(set) var avatarPreview: UIImage?
    /// Доступные источники аватара: камера — только там, где она есть.
    let avatarSources: [AvatarSource]
    /// Подготовка и загрузка изображения с прогрессом.
    let avatarUploader: AvatarUploader

    /// Загруженный файл аватара и его превью: к ним возвращается экран, если новая загрузка не удалась.
    private var uploadedAvatar: (fileId: Int, preview: UIImage?)?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    /// Растёт с каждым выбором и удалением аватара: результат прежней загрузки не применяется.
    @ObservationIgnored private var avatarGeneration = 0
    @ObservationIgnored private let groupService: GroupServiceProtocol
    @ObservationIgnored private let groupInfo: GroupInfoProviding
    @ObservationIgnored private let conversationList: ConversationListServiceProtocol
    @ObservationIgnored private let notifications: InAppNotificationServiceProtocol
    @ObservationIgnored private let router: CreateGroupRouter

    /// - Parameters:
    ///   - groupService: запрос `/groups/create`.
    ///   - groupInfo: состав групп — сюда применяется состав созданной группы.
    ///   - conversationList: список переписок — сюда добавляется созданная группа.
    ///   - filesService: загрузка изображения аватара.
    ///   - imageFileStore: временные файлы изображений.
    ///   - notifications: показ ошибок.
    ///   - router: роутер экрана.
    ///   - isCameraAvailable: есть ли камера; без неё вариант «Сделать фото» не предлагается.
    init(
        groupService: GroupServiceProtocol,
        groupInfo: GroupInfoProviding,
        conversationList: ConversationListServiceProtocol,
        filesService: FilesServiceProtocol,
        imageFileStore: ImageFileStoreProtocol,
        notifications: InAppNotificationServiceProtocol,
        router: CreateGroupRouter,
        isCameraAvailable: Bool
    ) {
        self.groupService = groupService
        self.groupInfo = groupInfo
        self.conversationList = conversationList
        self.notifications = notifications
        self.router = router
        avatarUploader = AvatarUploader(filesService: filesService, imageFileStore: imageFileStore)
        avatarSources = isCameraAvailable ? [.gallery, .camera] : [.gallery]
    }

    // MARK: - Состояние

    /// Ошибка названия для подсказки под полем; пустое название подсказкой не отмечается — просто нельзя создать.
    var nameError: GroupFieldError? {
        GroupValidator.validateName(name)
    }

    /// Ошибка описания для подсказки под полем.
    var descriptionError: GroupFieldError? {
        GroupValidator.validateDescription(groupDescription)
    }

    /// Можно ли создать группу: название и описание подходят, аватар не загружается, создание не идёт.
    var isCreateButtonEnabled: Bool {
        guard !isCreating, !avatarUploader.isUploading else { return false }
        return nameError == nil && descriptionError == nil
    }

    /// Можно ли закрыть лист смахиванием: не идёт создание и ничего не введено — иначе ввод легко потерять.
    var isInteractiveDismissDisabled: Bool {
        isCreating || !name.isEmpty || !groupDescription.isEmpty || hasAvatar
    }

    /// Есть ли выбранный аватар — в диалоге источников тогда есть «Удалить».
    var hasAvatar: Bool {
        avatarPreview != nil || uploadedAvatar != nil
    }

    // MARK: - Аватар

    /// Нажатие на аватар: выбор источника. Во время создания игнорируется.
    func didTapAvatar() {
        guard !isCreating else { return }
        isAvatarSourcesPresented = true
    }

    /// Выбран источник — открывается его пикер.
    /// - Parameter source: источник.
    func didSelectAvatarSource(_ source: AvatarSource) {
        presentedAvatarSource = source
    }

    /// Выбрано изображение: идущая загрузка отменяется, показывается превью нового и начинается его загрузка.
    /// - Parameter image: снимок с камеры или файл из галереи.
    func didPickImage(_ image: PickedImage) {
        presentedAvatarSource = nil
        guard !isCreating else {
            avatarUploader.discard(image)
            return
        }
        uploadTask?.cancel()
        avatarGeneration += 1
        let generation = avatarGeneration
        uploadTask = Task { [weak self] in
            await self?.uploadAvatar(image, generation: generation)
        }
    }

    /// Выбранный в галерее файл не удалось прочитать как изображение.
    func didFailToPickImage() {
        presentedAvatarSource = nil
        notifications.showError(CreateGroupStrings.avatarLoadFailed)
    }

    /// «Удалить» в диалоге аватара: загрузка отменяется, аватар сбрасывается.
    func didTapRemoveAvatar() {
        uploadTask?.cancel()
        uploadTask = nil
        avatarGeneration += 1
        avatarUploader.finish()
        uploadedAvatar = nil
        avatarPreview = nil
    }

    /// Готовит превью, загружает изображение и запоминает файл. Ошибка возвращает прежний аватар.
    /// - Parameters:
    ///   - image: выбранное изображение.
    ///   - generation: выбор, которому принадлежит загрузка.
    private func uploadAvatar(_ image: PickedImage, generation: Int) async {
        let preview = await Self.makePreview(of: image)
        guard generation == avatarGeneration else { return }
        avatarPreview = preview
        do {
            let remoteFile = try await avatarUploader.upload(image)
            guard generation == avatarGeneration else { return }
            uploadedAvatar = (remoteFile.fileId, preview)
            avatarPreview = preview
            avatarUploader.finish()
        } catch {
            guard generation == avatarGeneration else { return }
            avatarUploader.finish()
            avatarPreview = uploadedAvatar?.preview
            guard !(error is CancellationError) else { return }
            notifications.showError(error is ImageFileStoreError ? CreateGroupStrings.avatarLoadFailed : ErrorMessages.message(for: error))
        }
    }

    /// Уменьшенное превью изображения вне main.
    /// - Parameter image: выбранное изображение.
    /// - Returns: `nil` — файл не читается как изображение.
    private static func makePreview(of image: PickedImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let source: UIImage?
            switch image {
            case let .image(uiImage): source = uiImage
            case let .file(file): source = UIImage(contentsOfFile: file.url.path)
            }
            return source?.preparingThumbnail(of: CGSize(width: 300, height: 300)) ?? source
        }.value
    }

    // MARK: - Создание

    /// «Создать»: группа создаётся, применяется в состав групп и список переписок, экран завершается.
    func didTapCreate() {
        guard isCreateButtonEnabled else { return }
        isCreating = true
        Task { await create() }
    }

    /// «Отмена»: загрузка аватара отменяется, экран закрывается. Во время создания недоступна.
    func didTapCancel() {
        guard !isCreating else { return }
        cancelAvatarUpload()
        router.cancel()
    }

    /// Экран закрыт (в том числе смахиванием): идущая загрузка аватара отменяется.
    func didDisappear() {
        cancelAvatarUpload()
    }

    /// Отменяет загрузку аватара; временный файл удаляет сама загрузка.
    private func cancelAvatarUpload() {
        uploadTask?.cancel()
        uploadTask = nil
    }

    /// Запрос создания с обрезанными значениями; пустое описание не отправляется.
    private func create() async {
        defer { isCreating = false }
        let description = GroupValidator.normalized(groupDescription)
        do {
            let created = try await groupService.create(
                name: GroupValidator.normalized(name),
                description: description.isEmpty ? nil : description,
                avatarFileId: uploadedAvatar?.fileId
            )
            groupInfo.apply(created.groupInfo)
            conversationList.apply(created.conversation)
            router.finish(with: created.conversation)
        } catch {
            notifications.showError(Self.errorMessage(for: error))
        }
    }

    /// Текст ошибки создания: у названия и файла аватара — свои тексты.
    /// - Parameter error: ошибка запроса.
    private static func errorMessage(for error: Error) -> String {
        guard case let NetworkError.api(code) = error else { return ErrorMessages.message(for: error) }
        switch code {
        case NetworkError.Code.invalidName: return CreateGroupStrings.invalidName
        case NetworkError.Code.fileNotImage, NetworkError.Code.fileNotFound: return CreateGroupStrings.avatarLoadFailed
        default: return ErrorMessages.message(for: error)
        }
    }
}

extension CreateGroupViewModel {
    /// Текст варианта в диалоге источников.
    /// - Parameter source: источник.
    func title(for source: AvatarSource) -> String {
        switch source {
        case .gallery: CreateGroupStrings.avatarChooseFromGallery
        case .camera: CreateGroupStrings.avatarTakePhoto
        }
    }

    /// Подсказка под полем для ошибки; пустое название подсказкой не отмечается.
    /// - Parameter error: ошибка поля.
    func hint(for error: GroupFieldError?) -> String? {
        guard case let .tooLong(maxLength) = error else { return nil }
        return CreateGroupStrings.tooLong(maxLength: maxLength)
    }
}
