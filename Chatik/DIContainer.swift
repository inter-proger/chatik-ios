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
    let messageStorage: MessageStorageReading
    /// Единственный писатель сообщений в БД.
    let messageCache: MessageCacheServiceProtocol
    let messageSendQueue: MessageSendQueueProtocol
    let userDefaultsService: UserDefaultsServiceProtocol
    let sessionService: SessionServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol
    let messageTextValidator: MessageTextValidatorProtocol
    /// Форматтеры заголовков дней в ленте сообщений по языку.
    let messageDateHeaderFormatterProvider: MessageDateHeaderFormatterProviding
    /// Полночь, смена часового пояса и перевод часов — по ним лента пересобирает заголовки дней.
    let significantTimeChangeService: SignificantTimeChangeServiceProtocol
    let globalService: GlobalServiceProtocol
    let realtimeService: RealtimeServiceProtocol
    /// Очередь событий WebSocket между соединением и всеми потребителями.
    let realtimeEventQueue: RealtimeEventQueueProtocol
    /// Список переписок — единственный, кто пишет переписки в БД.
    let conversationListService: ConversationListServiceProtocol
    /// Начало работы с сервером после открытия сессии — общее для старта приложения и входа.
    let sessionWorkLauncher: SessionWorkStarting
    #if DEBUG
    /// Запуск по debug-сценарию из аргументов `-debugLogin` / `-debugPassword`; `nil` — обычный старт.
    let debugLoginLaunch: DebugLoginLaunch?
    #endif
    /// Черновики сообщений — единственный, кто пишет их в БД.
    let messageDraftService: MessageDraftServiceProtocol
    /// Отправка правок сообщений: запрос переживает уход с экрана.
    let messageEditService: MessageEditServiceProtocol
    /// Уведомления поверх приложения: ошибки экранов, новые сообщения.
    let notificationService: InAppNotificationServiceProtocol
    /// Роутеры списка чатов по сценам: открытые переписки и открытие переписки из уведомления.
    let conversationNavigator: ConversationNavigating
    /// Уведомления о новых сообщениях в неоткрытых переписках.
    let messageNotificationService: MessageNotificationServiceProtocol
    /// Прочтение переписок другими участниками — единственный, кто пишет его в БД.
    let memberReadService: MemberReadServiceProtocol
    /// Запросы `/groups/*`.
    let groupService: GroupServiceProtocol
    /// Состав групп — единственный, кто пишет его в БД.
    let groupInfoService: GroupInfoServiceProtocol
    /// Держит наблюдение за сетью, пока жив контейнер: при появлении сети WebSocket переподключается сразу.
    private let networkPathMonitor: NetworkPathMonitor
    /// Подписка кэша сообщений на очередь событий — живёт, пока жив контейнер.
    private let messageCacheSubscription: RealtimeSubscription
    /// Передаёт кэшу сообщений выход из аккаунта; `AuthService` держит наблюдателей слабо.
    private let messageCacheLogoutObserver: MessageCacheLogoutObserver
    /// Передаёт сервису черновиков выход из аккаунта; `AuthService` держит наблюдателей слабо.
    private let messageDraftLogoutObserver: MessageDraftLogoutObserver
    /// Передаёт кэшу сообщений удаление переписки; список держит наблюдателей слабо.
    private let messageCacheRemovalObserver: MessageCacheRemovalObserver

    private init() {
        // Хранилище открывается в фоне: открытие SQLite и возможная миграция не задерживают первый кадр.
        let storageContainer = BackgroundLoadedContainer { CoreDataStack.makeContainer() }
        let userDefaultsService = UserDefaultsService()
        // Черновики и очередь отправки создаются раньше сессии: она загружает их при восстановлении и открытии.
        let messageDraftService = MessageDraftService(
            storage: MessageDraftStorageService(container: storageContainer),
            backgroundTasks: BackgroundTaskRunner()
        )
        let messageDraftLogoutObserver = MessageDraftLogoutObserver(draftService: messageDraftService)
        self.messageDraftService = messageDraftService
        self.messageDraftLogoutObserver = messageDraftLogoutObserver
        let actionDispatcher = APIActionDispatcher()
        let sessionExpirationRelay = SessionExpirationRelay()
        // Код 2003 от любого запроса завершает сессию через `AuthService` — наблюдатели остановят работу с сессией,
        // и приложение переключится на экран авторизации.
        let networkService = NetworkService(
            onUnauthorized: { await sessionExpirationRelay.expireSession() },
            onActions: { await actionDispatcher.dispatch($0) }
        )
        self.userDefaultsService = userDefaultsService
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
        self.messageDateHeaderFormatterProvider = MessageDateHeaderFormatterProvider.default
        self.significantTimeChangeService = SignificantTimeChangeService()
        let realtimeEventQueue = RealtimeEventQueue()
        self.realtimeEventQueue = realtimeEventQueue
        let connectionMonitor = RealtimeConnectionMonitor()
        // Кэш подписывается первым: он получает каждое событие раньше остальных потребителей, и подписка появляется
        // до запуска соединения — очередь не хранит события для будущих подписчиков.
        let messageCache = MessageCacheService(storage: messageStorage, connectionMonitor: connectionMonitor)
        self.messageCache = messageCache
        self.messageCacheSubscription = MessageCacheService.subscribe(messageCache, to: realtimeEventQueue)
        let messageCacheLogoutObserver = MessageCacheLogoutObserver(messageCache: messageCache)
        self.messageCacheLogoutObserver = messageCacheLogoutObserver
        let conversationListService = ConversationListService(
            conversationService: conversationService,
            storage: ConversationStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            userCache: userCache
        )
        self.conversationListService = conversationListService
        let messageSendQueue = MessageSendQueue(
            messageService: messageService,
            messageCache: messageCache,
            outgoingMessageStorage: OutgoingMessageStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            positionUpdater: conversationListService,
            membership: conversationListService
        )
        self.messageSendQueue = messageSendQueue
        let messageEditService = MessageEditService(
            messageService: messageService,
            messageCache: messageCache,
            positionUpdater: conversationListService,
            draftService: messageDraftService
        )
        self.messageEditService = messageEditService
        let notificationService = InAppNotificationService()
        self.notificationService = notificationService
        let sessionService = SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer),
            dataLoaders: [messageDraftService, messageSendQueue]
        )
        self.sessionService = sessionService
        let globalService = GlobalService(networkService: networkService)
        let realtimeService = RealtimeService(
            globalService: globalService,
            connectionFactory: URLSessionWebSocketConnectionFactory(),
            sessionService: sessionService,
            authService: authService,
            eventQueue: realtimeEventQueue,
            connectionMonitor: connectionMonitor,
            userCache: userCache
        )
        self.globalService = globalService
        self.realtimeService = realtimeService
        let conversationNavigator = ConversationNavigator(
            notifications: notificationService,
            conversationList: conversationListService
        )
        self.conversationNavigator = conversationNavigator
        let messageNotificationService = MessageNotificationService(
            eventQueue: realtimeEventQueue,
            sessionService: sessionService,
            conversationList: conversationListService,
            userCache: userCache,
            navigator: conversationNavigator,
            notifications: notificationService
        )
        self.messageNotificationService = messageNotificationService
        let groupService = GroupService(networkService: networkService)
        self.groupService = groupService
        let groupInfoService = GroupInfoService(
            groupService: groupService,
            storage: GroupInfoStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            membership: conversationListService,
            removalMarks: conversationListService
        )
        self.groupInfoService = groupInfoService
        let memberReadService = MemberReadService(
            conversationService: conversationService,
            storage: MemberReadStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            sessionService: sessionService,
            membership: conversationListService,
            groupInfo: groupInfoService
        )
        self.memberReadService = memberReadService
        groupInfoService.addObserver(memberReadService)
        let messageCacheRemovalObserver = MessageCacheRemovalObserver(messageCache: messageCache)
        self.messageCacheRemovalObserver = messageCacheRemovalObserver
        // Каскад удаления переписки: каждый удаляет только свои данные о ней (`docs/group-chats.md`, решение 6).
        // Навигатор первым: экраны переписки закрываются до того, как остальные удалят её данные.
        conversationListService.addRemovalObserver(conversationNavigator)
        conversationListService.addRemovalObserver(messageCacheRemovalObserver)
        conversationListService.addRemovalObserver(memberReadService)
        conversationListService.addRemovalObserver(groupInfoService)
        conversationListService.addRemovalObserver(messageSendQueue)
        conversationListService.addRemovalObserver(messageDraftService)
        let sessionWorkLauncher = SessionWorkLauncher(
            conversationList: conversationListService,
            messageNotifications: messageNotificationService,
            memberReads: memberReadService,
            groupInfo: groupInfoService,
            messageDelivery: messageSendQueue,
            realtimeService: realtimeService
        )
        self.sessionWorkLauncher = sessionWorkLauncher
        #if DEBUG
        self.debugLoginLaunch = DebugLaunchArguments.parse(
            ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        ).map { arguments in
            DebugLoginLaunch(
                arguments: arguments,
                service: DebugLoginService(
                    authService: authService,
                    sessionService: sessionService,
                    sessionWork: sessionWorkLauncher
                )
            )
        }
        #endif
        // Соединение, очередь событий, список, очередь отправки, правки, кэш сообщений, черновики, прочтение другими
        // и подготовка уведомления о сообщении останавливаются, а уведомление прошлой сессии убирается в фазе
        // `authServiceWillLogout` (до запроса выхода), сессия завершается в `authServiceDidLogout` (после него) —
        // от порядка подписки это не зависит.
        authService.addObserver(realtimeService)
        authService.addObserver(realtimeEventQueue)
        authService.addObserver(conversationListService)
        authService.addObserver(messageSendQueue)
        authService.addObserver(messageEditService)
        authService.addObserver(messageCacheLogoutObserver)
        authService.addObserver(messageDraftLogoutObserver)
        authService.addObserver(notificationService)
        authService.addObserver(messageNotificationService)
        authService.addObserver(memberReadService)
        authService.addObserver(groupInfoService)
        authService.addObserver(sessionService)
        self.networkPathMonitor = NetworkPathMonitor { [weak realtimeService] in
            realtimeService?.networkDidBecomeAvailable()
        }
    }

    /// Лента переписки для открытого экрана.
    /// - Parameter conversationId: переписка.
    func makeMessagesListService(conversationId: Int) -> MessagesListServiceProtocol {
        MessagesListService(
            conversationId: conversationId,
            messageCache: messageCache,
            storage: messageStorage,
            messageService: messageService,
            eventQueue: realtimeEventQueue,
            messageSendQueue: messageSendQueue,
            membership: conversationListService
        )
    }
}
