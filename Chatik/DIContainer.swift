//
//  DIContainer.swift
//  Chatik
//

import Foundation

/// Единая точка сборки общих сервисов приложения.
@MainActor
final class DIContainer {
    static let shared = DIContainer()

    let networkService: NetworkServiceProtocol
    let authService: AuthServiceProtocol
    let profileService: ProfileServiceProtocol
    let filesService: FilesServiceProtocol
    let usersService: UsersServiceProtocol
    let conversationService: ConversationServiceProtocol
    let imageFileStore: ImageFileStoreProtocol
    let fileStorage: FileStorageServiceProtocol
    let userStorage: UserStorageServiceProtocol
    let conversationStorage: ConversationStorageServiceProtocol
    let userDefaultsService: UserDefaultsServiceProtocol
    let sessionService: SessionServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol

    private init() {
        let storageContainer = CoreDataStack.makeContainer()
        let userDefaultsService = UserDefaultsService()
        let sessionService = SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer)
        )
        // Код 2003 от любого запроса завершает сессию — приложение само переключится на экран авторизации.
        let networkService = NetworkService(onUnauthorized: { await sessionService.expire() })
        self.userDefaultsService = userDefaultsService
        self.sessionService = sessionService
        self.localizationService = LocalizationService(userDefaultsService: userDefaultsService)
        self.networkService = networkService
        self.authService = AuthService(networkService: networkService)
        self.profileService = ProfileService(networkService: networkService)
        self.filesService = FilesService(networkService: networkService)
        self.usersService = UsersService(networkService: networkService)
        self.conversationService = ConversationService(networkService: networkService)
        self.imageFileStore = ImageFileStore()
        self.fileStorage = FileStorageService(container: storageContainer)
        self.userStorage = UserStorageService(container: storageContainer)
        self.conversationStorage = ConversationStorageService(container: storageContainer)
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
    }
}
