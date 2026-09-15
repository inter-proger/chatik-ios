//
//  ProfileViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана профиля текущего пользователя. Показывает пользователя из сессии сразу,
/// а при открытии и pull-to-refresh обновляет его с сервера. Позволяет установить аватар из галереи или с камеры.
@MainActor
@Observable
final class ProfileViewModel {
    /// `true`, пока выполняется запрос профиля.
    private(set) var isLoading = false
    /// `true`, пока изображение кодируется, загружается на сервер и назначается аватаром.
    private(set) var isUploadingAvatar = false
    /// `true`, пока показан выбор источника аватара.
    var isAvatarSourcesPresented = false
    /// Источник, чей пикер сейчас на экране. `nil` — пикер скрыт.
    var presentedAvatarSource: AvatarSource?
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    /// Доступные источники аватара: камера предлагается только там, где она есть.
    let avatarSources: [AvatarSource]
    /// Имя файла аватара при загрузке; сервер хранит его как имя файла.
    static let avatarFilename = "avatar.\(ImageMIMEType.jpeg.fileExtension)"

    private let profileService: ProfileServiceProtocol
    private let filesService: FilesServiceProtocol
    private let imageEncoder: ImageEncoderProtocol
    private let sessionService: SessionServiceProtocol

    /// - Parameters:
    ///   - profileService: сервис профиля.
    ///   - filesService: сервис загрузки файлов — для отправки изображения аватара.
    ///   - imageEncoder: подготовка изображения к загрузке (уменьшение, JPEG).
    ///   - sessionService: сервис сессии; отсюда берётся текущий пользователь, сюда пишется обновлённый.
    ///   - isCameraAvailable: есть ли на устройстве камера; без неё вариант «Сделать фото» не предлагается.
    init(
        profileService: ProfileServiceProtocol,
        filesService: FilesServiceProtocol,
        imageEncoder: ImageEncoderProtocol,
        sessionService: SessionServiceProtocol,
        isCameraAvailable: Bool
    ) {
        self.profileService = profileService
        self.filesService = filesService
        self.imageEncoder = imageEncoder
        self.sessionService = sessionService
        avatarSources = isCameraAvailable ? [.gallery, .camera] : [.gallery]
    }

    /// Профиль для отображения — из текущей сессии. `nil` — сессии нет.
    var profile: ProfileDisplayModel? {
        sessionService.currentUser.map(ProfileDisplayModel.init)
    }

    /// Запрашивает актуальный профиль с сервера и обновляет сессию. Повторный вызов во время запроса игнорируется.
    /// При ошибке показывает сообщение, оставляя на экране данные из сессии.
    func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await profileService.fetchProfile()
            await sessionService.update(user: user)
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Обработчик нажатия на аватар: если аватара нет — предлагает выбрать источник изображения.
    /// С установленным аватаром и во время загрузки нажатие игнорируется.
    func didTapAvatar() {
        guard let profile, profile.avatarURL == nil, !isUploadingAvatar else { return }
        isAvatarSourcesPresented = true
    }

    /// Обработчик выбора источника: открывает соответствующий пикер.
    /// - Parameter source: выбранный пользователем источник.
    func didSelectAvatarSource(_ source: AvatarSource) {
        presentedAvatarSource = source
    }

    /// Обработчик выбранного изображения: закрывает пикер и запускает установку аватара.
    /// - Parameter image: снимок с камеры или файл из галереи.
    func didPickImage(_ image: PickedImage) {
        presentedAvatarSource = nil
        guard !isUploadingAvatar else { return }
        Task { await uploadAvatar(image) }
    }

    /// Обработчик ситуации, когда выбранный в галерее файл не удалось прочитать как изображение.
    func didFailToPickImage() {
        presentedAvatarSource = nil
        errorMessage = ProfileStrings.avatarLoadFailed
    }

    /// Кодирует изображение, загружает его на сервер, назначает аватаром и обновляет сессию.
    /// При ошибке на любом шаге показывает сообщение; аватар остаётся прежним.
    /// Ошибка подготовки изображения — это проблема выбранного файла, а не сети, поэтому текст у неё свой.
    /// - Parameter image: изображение для аватара.
    func uploadAvatar(_ image: PickedImage) async {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            let data = try await imageEncoder.encodeForUpload(image)
            let file = try await filesService.uploadImage(data: data, filename: Self.avatarFilename, type: .jpeg)
            let user = try await profileService.setAvatar(fileId: file.fileId)
            await sessionService.update(user: user)
        } catch is ImageEncoderError {
            errorMessage = ProfileStrings.avatarLoadFailed
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }
}
