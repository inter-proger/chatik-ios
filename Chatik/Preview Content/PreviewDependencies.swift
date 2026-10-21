//
//  PreviewDependencies.swift
//  Chatik
//

#if DEBUG
import UIKit

/// Зависимости для `#Preview` экранов: моки вместо сети и `UserDefaults`, хранилище CoreData в памяти, чтобы превью
/// не ходили на сервер и не трогали настройки и БД приложения, а состояния (загрузка, ошибка) были воспроизводимы.
@MainActor
enum PreviewDependencies {
    static let storageContainer = CoreDataStack.makeContainer(inMemory: true)
    static let userDefaultsService = UserDefaultsServicePreviewMock()
    /// Черновики превью — в БД превью; загружаются при восстановлении сессий превью.
    static let messageDraftService = MessageDraftService(
        storage: MessageDraftStorageService(container: storageContainer),
        backgroundTasks: BackgroundTaskRunner()
    )
    static let realtimeEventQueue = RealtimeEventQueue()
    /// Очередь отправки превью — в БД превью; загружается при восстановлении сессии превью.
    static let messageSendQueue = makeMessageSendQueue()
    static let sessionService = makeSessionService(
        userDefaultsService: userDefaultsService,
        dataLoaders: [messageDraftService, messageSendQueue]
    )
    static let localizationService = LocalizationService(userDefaultsService: userDefaultsService, systemLanguage: .ru)
    /// Уведомления превью: окна уведомлений в превью нет, ошибки не показываются.
    static let notificationService = InAppNotificationService()
    static let userCache = UserCacheService(
        usersService: UsersServicePreviewMock(),
        userStorage: UserStorageService(container: storageContainer)
    )

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
            sessionWork: SessionWorkPreviewMock(messageDelivery: messageSendQueue),
            localizationService: localizationService,
            signupValidator: SignupValidator(),
            loginValidator: LoginValidator(),
            notifications: notificationService,
            router: AuthRouter()
        )
    }

    /// ViewModel списка чатов над моками. Список сразу синхронизируется — видно индикатор «Обновление…».
    static func chatListViewModel() -> ChatListViewModel {
        let conversationList = ConversationListService(
            conversationService: ConversationServicePreviewMock(userCache: userCache),
            storage: ConversationStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            userCache: userCache
        )
        conversationList.start()
        conversationList.synchronize()
        let navigator = ConversationNavigator(notifications: notificationService, conversationList: conversationList)
        return ChatListViewModel(
            conversationList: conversationList,
            sessionService: sessionService,
            userCache: userCache,
            draftService: messageDraftService,
            unsentMessages: messageSendQueue,
            localizationService: localizationService,
            notifications: notificationService,
            navigator: navigator,
            messageNotifications: MessageNotificationService(
                eventQueue: realtimeEventQueue,
                sessionService: sessionService,
                conversationList: conversationList,
                userCache: userCache,
                navigator: navigator,
                notifications: notificationService
            ),
            router: ChatListRouter()
        )
    }

    /// ViewModel экрана переписки над моками. У превью собственная сессия — видно деление на входящие и исходящие.
    /// - Parameter conversation: открытая переписка; по умолчанию — групповая, с именами отправителей.
    static func chatViewModel(
        conversation: Conversation = Conversation(
            conversationId: 2, type: .group, memberIds: [1, 2, 3], name: "Команда", avatar: nil, opponentUserId: nil,
            lastMessage: nil, positionUpdatedAt: .now, updatedInfoAt: .now
        )
    ) -> ChatViewModel {
        let user = User(userId: 1, login: "ivan", name: "Иван Петров", avatar: nil)
        let messageService = MessageServicePreviewMock()
        let messageCache = MessageCacheService(
            storage: MessageStorageService(container: storageContainer),
            connectionMonitor: RealtimeConnectionMonitor()
        )
        let messageSendQueue = makeMessageSendQueue(messageService: messageService, messageCache: messageCache)
        let sessionService = makeSessionService(
            userDefaultsService: UserDefaultsServicePreviewMock(currentUser: user),
            dataLoaders: [messageDraftService, messageSendQueue]
        )
        Task {
            await sessionService.restore()
            messageSendQueue.resumeDeliveries()
        }
        return ChatViewModel(
            conversation: conversation,
            messagesList: MessagesListService(
                conversationId: conversation.conversationId,
                messageCache: messageCache,
                storage: MessageStorageService(container: storageContainer),
                messageService: messageService,
                eventQueue: realtimeEventQueue,
                messageSendQueue: messageSendQueue
            ),
            messageSendQueue: messageSendQueue,
            editService: MessageEditService(
                messageService: messageService,
                messageCache: messageCache,
                positionUpdater: ConversationPositionUpdatingPreviewMock(),
                draftService: messageDraftService
            ),
            sessionService: sessionService,
            draftService: messageDraftService,
            userCache: userCache,
            localizationService: localizationService,
            messageTextValidator: MessageTextValidator(),
            dateHeaderFormatterProvider: MessageDateHeaderFormatterProvider.default,
            timeChangeService: SignificantTimeChangeService(),
            notifications: notificationService
        )
    }

    /// Сессия над заданным хранилищем настроек; при выходе очищается БД превью, а не приложения, данные
    /// пользователя загружаются из БД превью.
    /// - Parameters:
    ///   - userDefaultsService: хранилище настроек превью.
    ///   - dataLoaders: загрузка данных пользователя при открытии сессии; по умолчанию — черновики превью.
    static func makeSessionService(
        userDefaultsService: UserDefaultsServiceProtocol,
        dataLoaders: [SessionDataLoading]? = nil
    ) -> SessionService {
        SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer),
            dataLoaders: dataLoaders ?? [messageDraftService]
        )
    }

    /// Очередь отправки над моком сети и БД превью.
    /// - Parameters:
    ///   - messageService: отправка сообщений; по умолчанию — мок превью.
    ///   - messageCache: кэш сообщений; по умолчанию — над БД превью.
    static func makeMessageSendQueue(
        messageService: MessageServiceProtocol = MessageServicePreviewMock(),
        messageCache: MessageCacheServiceProtocol? = nil
    ) -> MessageSendQueue {
        MessageSendQueue(
            messageService: messageService,
            messageCache: messageCache ?? MessageCacheService(
                storage: MessageStorageService(container: storageContainer),
                connectionMonitor: RealtimeConnectionMonitor()
            ),
            outgoingMessageStorage: OutgoingMessageStorageService(container: storageContainer),
            eventQueue: realtimeEventQueue,
            positionUpdater: ConversationPositionUpdatingPreviewMock()
        )
    }

    /// ViewModel экрана создания личного диалога над моками. У превью собственная сессия — в списке видно,
    /// что текущий пользователь из него исключён.
    /// - Parameter user: пользователь сессии; он же есть в списке мока и должен быть отфильтрован.
    static func createSingleConversationViewModel(
        user: User = User(userId: 1, login: "ivan", name: "Иван Петров", avatar: nil)
    ) -> CreateSingleConversationViewModel {
        let sessionService = makeSessionService(userDefaultsService: UserDefaultsServicePreviewMock(currentUser: user))
        Task { await sessionService.restore() }
        return CreateSingleConversationViewModel(
            usersService: UsersServicePreviewMock(),
            conversationService: ConversationServicePreviewMock(),
            sessionService: sessionService,
            notifications: notificationService,
            router: CreateSingleConversationRouter(onFinish: { _ in })
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
        let sessionService = makeSessionService(userDefaultsService: UserDefaultsServicePreviewMock(currentUser: user))
        Task { await sessionService.restore() }
        return ProfileViewModel(
            profileService: ProfileServicePreviewMock(profileResult: profileResult ?? .success(user)),
            filesService: FilesServicePreviewMock(),
            imageFileStore: ImageFileStore(),
            sessionService: sessionService,
            authService: makeAuthService(observers: [sessionService]),
            notifications: notificationService,
            // Как в приложении: на симуляторе камеры нет, и «Сделать фото» предлагаться не должно —
            // `UIImagePickerController` с `.camera` без камеры падает.
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
    }

    /// Мок сервиса авторизации с подписанными наблюдателями — выход в превью ведёт себя как в приложении.
    /// - Parameter observers: наблюдатели выхода в порядке подписки.
    private static func makeAuthService(observers: [AuthServiceObserver]) -> AuthServicePreviewMock {
        let authService = AuthServicePreviewMock()
        observers.forEach(authService.addObserver)
        return authService
    }
}

/// Мок сервиса файлов для превью: «загружает» любое изображение с задержкой, равномерно сообщая прогресс,
/// и возвращает файл-заглушку.
final class FilesServicePreviewMock: FilesServiceProtocol {
    private let delay: Duration
    /// На сколько шагов разбита «отправка» — столько раз будет сообщён прогресс.
    private let progressSteps = 10

    init(delay: Duration = .seconds(1.5)) {
        self.delay = delay
    }

    func uploadImage(
        file: ImageFile,
        filename: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile {
        for step in 1...progressSteps {
            try await Task.sleep(for: delay / progressSteps)
            onProgress(Double(step) / Double(progressSteps))
        }
        return RemoteFile(fileId: 1, type: .image, url: URL(string: "http://localhost:8080/static/uploads/avatar.jpg")!, size: 0, filename: filename, fileExtension: file.type.fileExtension, smallURL: nil)
    }

    func fetchFile(id: Int) async throws -> RemoteFile {
        try await Task.sleep(for: delay)
        return RemoteFile(fileId: id, type: .image, url: URL(string: "http://localhost:8080/static/uploads/avatar.jpg")!, size: 0, filename: "avatar.jpg", fileExtension: "jpg", smallURL: nil)
    }
}

/// Мок сервиса пользователей для превью: отдаёт одну страницу пользователей, отфильтрованную по запросу, с задержкой.
final class UsersServicePreviewMock: UsersServiceProtocol {
    private let users = [
        User(userId: 1, login: "ivan", name: "Иван Петров", avatar: nil),
        User(userId: 2, login: "maria", name: "Мария Иванова", avatar: nil),
        User(userId: 3, login: "petr", name: "Пётр Сидоров", avatar: nil),
        User(userId: 4, login: "olga", name: "Ольга Смирнова", avatar: nil),
    ]
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    func fetchUsers(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage {
        try await Task.sleep(for: delay)
        guard maxId == nil else { return UsersPage(users: [], nextMaxId: nil, hasNext: false) }
        let found = users.filter { user in
            guard let query, !query.isEmpty else { return true }
            return user.name.localizedCaseInsensitiveContains(query) || user.login.localizedCaseInsensitiveContains(query)
        }
        return UsersPage(users: found, nextMaxId: found.last?.userId, hasNext: false)
    }

    func fetchUsers(ids: [Int]) async throws -> UsersBatch {
        try await Task.sleep(for: delay)
        let found = users.filter { ids.contains($0.userId) }
        return UsersBatch(users: found, notFoundIds: ids.filter { id in !found.contains { $0.userId == id } })
    }
}

/// Мок сервиса переписок для превью: «создаёт» переписку с задержкой.
final class ConversationServicePreviewMock: ConversationServiceProtocol {
    private let delay: Duration
    /// Кэш, которому мок передаёт участников переписок, как сетевой слой передаёт action `users`.
    /// `nil` — участники никуда не передаются.
    private let userCache: UserCacheServiceProtocol?

    init(delay: Duration = .seconds(1.5), userCache: UserCacheServiceProtocol? = nil) {
        self.delay = delay
        self.userCache = userCache
    }

    func createSingle(userId: Int) async throws -> Conversation {
        try await Task.sleep(for: delay)
        let conversation = Conversation(
            conversationId: 1,
            type: .single,
            memberIds: [1, userId],
            name: nil,
            avatar: nil,
            opponentUserId: userId,
            lastMessage: nil,
            positionUpdatedAt: .now,
            updatedInfoAt: .now
        )
        await sendUsersAction(for: [conversation])
        return conversation
    }

    /// Отдаёт две переписки на первую страницу без фильтра; на остальные запросы — пустую страницу.
    func fetchConversations(filter: ConversationListFilter, count: Int?) async throws -> ConversationsPage {
        try await Task.sleep(for: delay)
        guard filter == .none(offset: nil) else { return ConversationsPage(conversations: [], hasNext: false) }
        await sendUsersAction(for: previewConversations)
        return ConversationsPage(conversations: previewConversations, hasNext: false)
    }

    func fetchConversations(ids: [Int]) async throws -> ConversationsBatch {
        try await Task.sleep(for: delay)
        let found = previewConversations.filter { ids.contains($0.conversationId) }
        return ConversationsBatch(conversations: found, notFoundIds: ids.filter { id in !found.contains { $0.id == id } })
    }

    /// Переписки списка: личная — с последним сообщением, групповая — без сообщений.
    private var previewConversations: [Conversation] {
        let now = ServerTime.now
        return [
            Conversation(
                conversationId: 1, type: .single, memberIds: [1, 2], name: nil, avatar: nil, opponentUserId: 2,
                lastMessage: LastMessage(messageId: 1, type: .text, text: "Привет! Во сколько созвон?", updatedAt: now),
                positionUpdatedAt: now, updatedInfoAt: now
            ),
            Conversation(
                conversationId: 2, type: .group, memberIds: [1, 2, 3], name: "Команда", avatar: nil, opponentUserId: nil,
                lastMessage: nil, positionUpdatedAt: now.adding(milliseconds: -86_400_000), updatedInfoAt: now
            ),
        ]
    }

    /// Передаёт участников переписок в кэш и ждёт загрузки отсутствующих — как `APIActionDispatcher`.
    /// - Parameter conversations: переписки из «ответа».
    private func sendUsersAction(for conversations: [Conversation]) async {
        guard let userCache else { return }
        let ids = Array(Set(conversations.flatMap(\.memberIds))).sorted()
        await userCache.loadUsers(ids: ids)
    }
}

/// Мок сервиса сообщений для превью: отдаёт одну страницу сообщений и «отправляет» сообщения с задержкой.
final class MessageServicePreviewMock: MessageServiceProtocol, Sendable {
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    func fetchMessages(conversationId: Int, filter: MessageListFilter) async throws -> MessagesPage {
        try await Task.sleep(for: delay)
        guard filter == .block(nil) else { return MessagesPage(messages: [], nextBlockId: nil, hasNext: false) }
        let texts = ["Привет всем!", "Привет! Во сколько созвон?", "Давайте в 15:00", "Подходит", "Договорились"]
        let messages = texts.enumerated().map { index, text in
            makeMessage(id: index + 1, conversationId: conversationId, senderId: index % 3 + 1, text: text, clientId: "preview-\(index + 1)")
        }
        return MessagesPage(messages: messages.reversed(), nextBlockId: nil, hasNext: false)
    }

    func fetchBlocks(ids: [Int]) async throws -> MessageBlocksBatch {
        try await Task.sleep(for: delay)
        return MessageBlocksBatch(blocks: [], notFoundIds: ids)
    }

    func send(conversationId: Int, text: String, clientId: String) async throws -> Message {
        try await Task.sleep(for: delay)
        return makeMessage(id: Int.random(in: 100...10_000), conversationId: conversationId, senderId: 1, text: text, clientId: clientId)
    }

    func edit(messageId: Int, newText: String) async throws -> MessageEditResult {
        try await Task.sleep(for: delay)
        return MessageEditResult(message: makeMessage(id: messageId, conversationId: 1, senderId: 1, text: newText), lastMessage: nil)
    }

    /// Собирает текстовое сообщение, отправленное только что.
    /// - Parameters:
    ///   - id: идентификатор сообщения.
    ///   - conversationId: переписка.
    ///   - senderId: отправитель.
    ///   - text: текст.
    ///   - clientId: идентификатор клиента-отправителя; по умолчанию — новый.
    private func makeMessage(id: Int, conversationId: Int, senderId: Int, text: String, clientId: String = UUID().uuidString) -> Message {
        Message(messageId: id, clientId: clientId, conversationId: conversationId, blockId: 1, senderId: senderId, type: .text, text: text, isEdited: false, createdAt: .now, updatedAt: .now)
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
/// Выход всегда успешен и оповещает наблюдателей так же, как настоящий сервис (`AuthServiceObservers`).
@MainActor
final class AuthServicePreviewMock: AuthServiceProtocol {
    private let authResult: Result<User, Error>
    private let delay: Duration
    private let observers = AuthServiceObservers()

    init(
        authResult: Result<User, Error> = .success(User(userId: 1, login: "ivan", name: "Иван", avatar: nil)),
        delay: Duration = .seconds(1.5)
    ) {
        self.authResult = authResult
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

    /// Выход с задержкой вместо запроса.
    func logout() async {
        await observers.performLogout(reason: .userInitiated) { [delay] in
            try? await Task.sleep(for: delay)
        }
    }

    /// Истечение сессии без задержки — как в настоящем сервисе, запроса нет.
    func expireSession() {
        Task { await observers.performLogout(reason: .sessionExpired) {} }
    }

    func addObserver(_ observer: AuthServiceObserver) {
        observers.add(observer)
    }

    func removeObserver(_ observer: AuthServiceObserver) {
        observers.remove(observer)
    }
}

/// Начало работы с сервером для превью: запускает только отправку очереди превью — соединения в превью нет,
/// а список переписок экран входа не показывает.
@MainActor
final class SessionWorkPreviewMock: SessionWorkStarting {
    private let messageDelivery: MessageDeliveryResuming

    /// - Parameter messageDelivery: очередь отправки превью.
    init(messageDelivery: MessageDeliveryResuming) {
        self.messageDelivery = messageDelivery
    }

    func startSessionWork() {
        messageDelivery.resumeDeliveries()
    }
}

/// Список чатов для превью экрана переписки: подъём переписки по ответу на отправку там не виден.
@MainActor
final class ConversationPositionUpdatingPreviewMock: ConversationPositionUpdating {
    func applySentMessage(_ message: Message) {}
    func applyEditedMessage(_ message: Message, lastMessage: LastMessage?) {}
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
