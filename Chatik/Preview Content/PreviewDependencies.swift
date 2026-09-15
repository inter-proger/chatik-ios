//
//  PreviewDependencies.swift
//  Chatik
//

#if DEBUG
import Foundation

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
