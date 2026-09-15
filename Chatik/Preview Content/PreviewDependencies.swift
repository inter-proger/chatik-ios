//
//  PreviewDependencies.swift
//  Chatik
//

#if DEBUG
import UIKit

/// Зависимости для `#Preview` экранов: моки вместо сети и `UserDefaults`, чтобы превью не ходили
/// на сервер и не трогали настройки приложения, а состояния (загрузка, ошибка) были воспроизводимы.
@MainActor
enum PreviewDependencies {
    static let userDefaultsService = UserDefaultsServicePreviewMock()
    static let sessionService = SessionService(userDefaultsService: userDefaultsService)
    static let localizationService = LocalizationService(userDefaultsService: userDefaultsService, systemLanguage: .ru)

    /// ViewModel экрана авторизации над моками.
    /// - Parameters:
    ///   - mode: режим экрана.
    ///   - authResult: чем отвечает сервис авторизации на регистрацию / вход.
    static func authViewModel(
        mode: AuthMode,
        authResult: Result<User, Error> = .success(User(userId: 1, login: "ivan", name: "Иван", avatar: nil))
    ) -> AuthViewModel {
        AuthViewModel(
            mode: mode,
            authService: AuthServicePreviewMock(authResult: authResult),
            sessionService: sessionService,
            localizationService: localizationService,
            signupValidator: SignupValidator(),
            loginValidator: LoginValidator(),
            router: AuthRouter()
        )
    }

    /// ViewModel списка чатов над моками.
    /// - Parameter logoutResult: чем отвечает сервис авторизации на выход.
    static func chatListViewModel(logoutResult: Result<Void, Error> = .success(())) -> ChatListViewModel {
        ChatListViewModel(
            authService: AuthServicePreviewMock(logoutResult: logoutResult),
            sessionService: sessionService,
            router: ChatListRouter()
        )
    }

    /// ViewModel профиля над моками. У превью собственная сессия, восстановленная из хранилища с пользователем `user`, —
    /// общий `sessionService` не трогается, и превью не зависят друг от друга.
    /// - Parameters:
    ///   - user: пользователь сессии; экрану есть что показать сразу, до ответа сервиса.
    ///   - profileResult: чем отвечает сервис профиля на запрос; по умолчанию — тем же `user`.
    static func profileViewModel(
        user: User = User(userId: 1, login: "ivan", name: "Иван", avatar: nil),
        profileResult: Result<User, Error>? = nil
    ) -> ProfileViewModel {
        let sessionService = SessionService(userDefaultsService: UserDefaultsServicePreviewMock(currentUser: user))
        Task { await sessionService.restore() }
        return ProfileViewModel(
            profileService: ProfileServicePreviewMock(profileResult: profileResult ?? .success(user)),
            filesService: FilesServicePreviewMock(),
            imageEncoder: ImageEncoder(),
            sessionService: sessionService,
            // Как в приложении: на симуляторе камеры нет, и «Сделать фото» предлагаться не должно —
            // `UIImagePickerController` с `.camera` без камеры падает.
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
    }
}

/// Мок сервиса файлов для превью: «загружает» любое изображение с задержкой и возвращает файл-заглушку.
final class FilesServicePreviewMock: FilesServiceProtocol {
    private let delay: Duration

    init(delay: Duration = .seconds(1.5)) {
        self.delay = delay
    }

    func uploadImage(data: Data, filename: String, type: ImageMIMEType) async throws -> RemoteFile {
        try await Task.sleep(for: delay)
        return RemoteFile(fileId: 1, type: .image, url: URL(string: "http://localhost:8080/static/uploads/avatar.jpg")!, size: data.count, filename: filename, fileExtension: type.fileExtension, smallURL: nil)
    }

    func fetchFile(id: Int) async throws -> RemoteFile {
        try await Task.sleep(for: delay)
        return RemoteFile(fileId: id, type: .image, url: URL(string: "http://localhost:8080/static/uploads/avatar.jpg")!, size: 0, filename: "avatar.jpg", fileExtension: "jpg", smallURL: nil)
    }
}

/// Мок сервиса профиля для превью: отвечает заданным результатом с задержкой, чтобы было видно состояние загрузки.
final class ProfileServicePreviewMock: ProfileServiceProtocol {
    private let profileResult: Result<User, Error>
    private let delay: Duration

    init(profileResult: Result<User, Error>, delay: Duration = .seconds(1.5)) {
        self.profileResult = profileResult
        self.delay = delay
    }

    func fetchProfile() async throws -> User {
        try await Task.sleep(for: delay)
        return try profileResult.get()
    }

    func setAvatar(fileId: Int) async throws -> User {
        try await Task.sleep(for: delay)
        return try profileResult.get()
    }

    func removeAvatar() async throws -> User {
        try await Task.sleep(for: delay)
        return try profileResult.get()
    }
}

/// Мок сервиса авторизации для превью: отвечает заданным результатом с задержкой, чтобы было видно состояние загрузки.
final class AuthServicePreviewMock: AuthServiceProtocol {
    private let authResult: Result<User, Error>
    private let logoutResult: Result<Void, Error>
    private let delay: Duration

    init(
        authResult: Result<User, Error> = .success(User(userId: 1, login: "ivan", name: "Иван", avatar: nil)),
        logoutResult: Result<Void, Error> = .success(()),
        delay: Duration = .seconds(1.5)
    ) {
        self.authResult = authResult
        self.logoutResult = logoutResult
        self.delay = delay
    }

    func signup(login: String, password: String, name: String) async throws -> User {
        try await Task.sleep(for: delay)
        return try authResult.get()
    }

    func login(login: String, password: String) async throws -> User {
        try await Task.sleep(for: delay)
        return try authResult.get()
    }

    func logout() async throws {
        try await Task.sleep(for: delay)
        try logoutResult.get()
    }
}

/// Хранилище настроек для превью: держит значения в памяти, `UserDefaults` не трогает.
actor UserDefaultsServicePreviewMock: UserDefaultsServiceProtocol {
    private var storedUser: User?
    private var storedLanguage: AppLanguage?

    /// - Parameter currentUser: пользователь, который «уже сохранён» к моменту старта превью.
    init(currentUser: User? = nil) {
        storedUser = currentUser
    }

    func currentUser() -> User? { storedUser }

    func setCurrentUser(_ user: User?) {
        storedUser = user
    }

    func language() -> AppLanguage? { storedLanguage }

    func setLanguage(_ language: AppLanguage) {
        storedLanguage = language
    }
}
#endif
