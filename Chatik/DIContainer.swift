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
    let globalService: GlobalServiceProtocol
    let realtimeService: RealtimeServiceProtocol
    /// Держит наблюдение за сетью, пока жив контейнер: при появлении сети WebSocket переподключается сразу.
    private let networkPathMonitor: NetworkPathMonitor

    private init() {
        // Хранилище открывается в фоне: открытие SQLite и возможная миграция не задерживают первый кадр.
        let storageContainer = BackgroundLoadedContainer { CoreDataStack.makeContainer() }
        let userDefaultsService = UserDefaultsService()
        let sessionService = SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer)
        )
        let actionDispatcher = APIActionDispatcher()
        let sessionExpirationRelay = SessionExpirationRelay()
        // Код 2003 от любого запроса завершает сессию через `AuthService` — наблюдатели остановят работу с сессией,
        // и приложение переключится на экран авторизации.
        let networkService = NetworkService(
            onUnauthorized: { await sessionExpirationRelay.expireSession() },
            onActions: { await actionDispatcher.dispatch($0) }
        )
        self.userDefaultsService = userDefaultsService
        self.sessionService = sessionService
        self.localizationService = LocalizationService(userDefaultsService: userDefaultsService)
        self.networkService = networkService
        let authService = AuthService(networkService: networkService)
        sessionExpirationRelay.authService = authService
        self.authService = authService
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
        let conversationStorage = ConversationStorageService(container: storageContainer)
        let messageStorage = MessageStorageService(container: storageContainer)
        self.conversationStorage = conversationStorage
        self.messageStorage = messageStorage
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
        self.messageTextValidator = MessageTextValidator()
        let globalService = GlobalService(networkService: networkService)
        let realtimeService = RealtimeService(
            globalService: globalService,
            connectionFactory: URLSessionWebSocketConnectionFactory(),
            sessionService: sessionService,
            authService: authService,
            conversationStorage: conversationStorage,
            messageStorage: messageStorage,
            userCache: userCache
        )
        self.globalService = globalService
        self.realtimeService = realtimeService
        // Соединение закрывается в фазе `authServiceWillLogout` (до запроса выхода), сессия завершается
        // в `authServiceDidLogout` (после него) — от порядка подписки это не зависит.
        authService.addObserver(realtimeService)
        authService.addObserver(sessionService)
        self.networkPathMonitor = NetworkPathMonitor { [weak realtimeService] in
            realtimeService?.networkDidBecomeAvailable()
        }
    }
}
