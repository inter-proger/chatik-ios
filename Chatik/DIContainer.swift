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
    let messageStorage: MessageStorageServiceProtocol
    let messageSendQueue: MessageSendQueueProtocol
    let userDefaultsService: UserDefaultsServiceProtocol
    let sessionService: SessionServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol
    let messageTextValidator: MessageTextValidatorProtocol
    let globalService: GlobalServiceProtocol
    let realtimeService: RealtimeServiceProtocol
    /// Очередь событий WebSocket между соединением и всеми потребителями.
    let realtimeEventQueue: RealtimeEventQueueProtocol
    /// Список переписок — единственный, кто пишет переписки в БД.
    let conversationListService: ConversationListServiceProtocol
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
        let conversationService = ConversationService(networkService: networkService)
        self.conversationService = conversationService
        let messageService = MessageService(networkService: networkService)
        self.messageService = messageService
        self.imageFileStore = ImageFileStore()
        self.fileStorage = FileStorageService(container: storageContainer)
        self.userStorage = userStorage
        let messageStorage = MessageStorageService(container: storageContainer)
        self.messageStorage = messageStorage
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
        self.messageTextValidator = MessageTextValidator()
        let realtimeEventQueue = RealtimeEventQueue()
        self.realtimeEventQueue = realtimeEventQueue
        let conversationListService = ConversationListService(
            conversationService: conversationService,
            storage: ConversationStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            userCache: userCache
        )
        self.conversationListService = conversationListService
        let globalService = GlobalService(networkService: networkService)
        let realtimeService = RealtimeService(
            globalService: globalService,
            connectionFactory: URLSessionWebSocketConnectionFactory(),
            sessionService: sessionService,
            authService: authService,
            eventQueue: realtimeEventQueue,
            messageStorage: messageStorage,
            userCache: userCache
        )
        self.globalService = globalService
        self.realtimeService = realtimeService
        let messageSendQueue = MessageSendQueue(
            messageService: messageService,
            messageStorage: messageStorage,
            outgoingMessageStorage: OutgoingMessageStorageService(container: storageContainer),
            sessionService: sessionService,
            eventQueue: realtimeEventQueue,
            positionUpdater: conversationListService
        )
        self.messageSendQueue = messageSendQueue
        // Соединение, очередь событий, список и очередь отправки останавливаются в фазе `authServiceWillLogout`
        // (до запроса выхода), сессия завершается в `authServiceDidLogout` (после него) — от порядка подписки
        // это не зависит.
        authService.addObserver(realtimeService)
        authService.addObserver(realtimeEventQueue)
        authService.addObserver(conversationListService)
        authService.addObserver(messageSendQueue)
        authService.addObserver(sessionService)
        self.networkPathMonitor = NetworkPathMonitor { [weak realtimeService] in
            realtimeService?.networkDidBecomeAvailable()
        }
    }
}
