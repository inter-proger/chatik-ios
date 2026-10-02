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
    let userCache: UserCacheServiceProtocol
    let conversationService: ConversationServiceProtocol
    let messageService: MessageServiceProtocol
    let imageFileStore: ImageFileStoreProtocol
    let fileStorage: FileStorageServiceProtocol
    let userStorage: UserStorageServiceProtocol
    let conversationStorage: ConversationStorageServiceProtocol
    let messageStorage: MessageStorageServiceProtocol
    let userDefaultsService: UserDefaultsServiceProtocol
    let sessionService: SessionServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol
    let messageTextValidator: MessageTextValidatorProtocol

    private init() {
        // Хранилище открывается в фоне: открытие SQLite и возможная миграция не задерживают первый кадр.
        let storageContainer = BackgroundLoadedContainer { CoreDataStack.makeContainer() }
        let userDefaultsService = UserDefaultsService()
        let sessionService = SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer)
        )
        let actionDispatcher = APIActionDispatcher()
        // Код 2003 от любого запроса завершает сессию — приложение само переключится на экран авторизации.
        let networkService = NetworkService(
            onUnauthorized: { await sessionService.expire() },
            onActions: { await actionDispatcher.dispatch($0) }
        )
        self.userDefaultsService = userDefaultsService
        self.sessionService = sessionService
        self.localizationService = LocalizationService(userDefaultsService: userDefaultsService)
        self.networkService = networkService
        self.authService = AuthService(networkService: networkService)
        self.profileService = ProfileService(networkService: networkService)
        self.filesService = FilesService(networkService: networkService)
        let usersService = UsersService(networkService: networkService)
        let userStorage = UserStorageService(container: storageContainer)
        let userCache = UserCacheService(usersService: usersService, userStorage: userStorage)
        actionDispatcher.userCache = userCache
        self.usersService = usersService
        self.userCache = userCache
        self.conversationService = ConversationService(networkService: networkService)
        self.messageService = MessageService(networkService: networkService)
        self.imageFileStore = ImageFileStore()
        self.fileStorage = FileStorageService(container: storageContainer)
        self.userStorage = userStorage
        self.conversationStorage = ConversationStorageService(container: storageContainer)
        self.messageStorage = MessageStorageService(container: storageContainer)
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
        self.messageTextValidator = MessageTextValidator()
    }
}
