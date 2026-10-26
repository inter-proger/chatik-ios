//
//  ProfileViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана профиля текущего пользователя. Показывает пользователя из сессии сразу,
/// а при открытии и pull-to-refresh обновляет его с сервера. Позволяет установить аватар из галереи или с камеры
/// и выйти из аккаунта.
///
/// Здесь — хранимое состояние, зависимости, `init` и действия, которые мутируют состояние.
/// Обработчики выбора фото вынесены в `ProfileViewModel+AvatarPicking`.
@MainActor
@Observable
final class ProfileViewModel {
    /// `true`, пока выполняется запрос профиля.
    private(set) var isLoading = false
    /// `true`, пока показан выбор источника аватара.
    var isAvatarSourcesPresented = false
    /// Источник, чей пикер сейчас на экране. `nil` — пикер скрыт.
    var presentedAvatarSource: AvatarSource?
    /// `true`, пока показан попап подтверждения выхода.
    var isLogoutConfirmationPresented = false
    /// `true`, пока выполняется запрос выхода.
    private(set) var isLoggingOut = false

    /// Доступные источники аватара: камера предлагается только там, где она есть.
    let avatarSources: [AvatarSource]

    private let profileService: ProfileServiceProtocol
    /// Подготовка и загрузка изображения; нужен и `ProfileViewModel+AvatarPicking`, поэтому не `private`.
    let avatarUploader: AvatarUploader
    private let sessionService: SessionServiceProtocol
    private let authService: AuthServiceProtocol
    /// Показ ошибок; нужен и `ProfileViewModel+AvatarPicking`, поэтому не `private`.
    let notifications: InAppNotificationServiceProtocol

    /// - Parameters:
    ///   - profileService: сервис профиля.
    ///   - filesService: сервис загрузки файлов — для отправки изображения аватара.
    ///   - imageFileStore: временные файлы изображений для загрузки.
    ///   - sessionService: сервис сессии; отсюда берётся текущий пользователь, сюда пишется обновлённый.
    ///   - authService: сервис авторизации — для выхода из аккаунта.
    ///   - notifications: показ ошибок загрузки профиля и аватара.
    ///   - isCameraAvailable: есть ли на устройстве камера; без неё вариант «Сделать фото» не предлагается.
    init(
        profileService: ProfileServiceProtocol,
        filesService: FilesServiceProtocol,
        imageFileStore: ImageFileStoreProtocol,
        sessionService: SessionServiceProtocol,
        authService: AuthServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        isCameraAvailable: Bool
    ) {
        self.profileService = profileService
        avatarUploader = AvatarUploader(filesService: filesService, imageFileStore: imageFileStore)
        self.sessionService = sessionService
        self.authService = authService
        self.notifications = notifications
        avatarSources = isCameraAvailable ? [.gallery, .camera] : [.gallery]
    }

    /// Имя файла аватара при загрузке; сервер хранит его как имя файла.
    /// - Parameter type: формат загружаемого файла — задаёт расширение.
    static func avatarFilename(for type: ImageMIMEType) -> String {
        AvatarUploader.filename(for: type)
    }

    /// Прогресс установки аватара. `nil` — установка не идёт. Иначе доля отправленного изображения от 0 до 1:
    /// 0 — файл готовится к отправке, 1 — файл отправлен и аватар назначается.
    var avatarUploadProgress: Double? {
        avatarUploader.progress
    }

    /// Профиль для отображения — из текущей сессии. `nil` — сессии нет.
    var profile: ProfileDisplayModel? {
        sessionService.currentUser.map(ProfileDisplayModel.init)
    }

    /// `true`, пока файл изображения готовится, загружается на сервер и назначается аватаром.
    var isUploadingAvatar: Bool {
        avatarUploadProgress != nil
    }

    // MARK: - Профиль

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
            notifications.showError(ErrorMessages.message(for: error))
        }
    }

    // MARK: - Установка аватара

    /// Готовит файл изображения, загружает его на сервер как есть, назначает аватаром и обновляет сессию.
    /// При ошибке на любом шаге показывает сообщение; аватар остаётся прежним.
    /// Ошибка подготовки файла — это проблема выбранного изображения, а не сети, поэтому текст у неё свой.
    /// - Parameter image: изображение для аватара.
    func uploadAvatar(_ image: PickedImage) async {
        defer { avatarUploader.finish() }

        do {
            let remoteFile = try await avatarUploader.upload(image)
            let user = try await profileService.setAvatar(fileId: remoteFile.fileId)
            await sessionService.update(user: user)
        } catch is ImageFileStoreError {
            notifications.showError(ProfileStrings.avatarLoadFailed)
        } catch {
            notifications.showError(ErrorMessages.message(for: error))
        }
    }

    /// Обновляет прогресс отправки; только растёт, вне загрузки игнорируется (`AvatarUploader.didSendBytes`).
    /// - Parameter progress: доля отправленных данных от 0 до 1.
    func didSendAvatarBytes(_ progress: Double) {
        avatarUploader.didSendBytes(progress)
    }

    // MARK: - Выход

    /// Обработчик кнопки «Выйти»: показывает попап подтверждения, если выход ещё не выполняется.
    func didTapLogout() {
        guard !isLoggingOut else { return }
        isLogoutConfirmationPresented = true
    }

    /// Обработчик подтверждения в попапе: запускает выход. Отмена ничего не делает — попап
    /// закрывается самим `Alert` через привязку `isLogoutConfirmationPresented`.
    func didTapConfirmLogout() {
        guard !isLoggingOut else { return }
        Task { await logout() }
    }

    /// Выходит из аккаунта. Выход не может не удаться: устройство разлогинивается при любом ответе сервера,
    /// а сессия, WebSocket и список чатов реагируют на него сами — как наблюдатели `AuthService`.
    /// Приложение переключится на экран авторизации.
    func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        await authService.logout()
    }
}
