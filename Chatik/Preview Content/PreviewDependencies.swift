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
    static let sessionService = makeSessionService(userDefaultsService: userDefaultsService)
    static let localizationService = LocalizationService(userDefaultsService: userDefaultsService, systemLanguage: .ru)
    static let userCache = UserCacheService(
        usersService: UsersServicePreviewMock(),
        userStorage: UserStorageService(container: storageContainer)
    )
    static let realtimeService = RealtimeServicePreviewMock()

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
            realtimeService: realtimeService,
            localizationService: localizationService,
            signupValidator: SignupValidator(),
            loginValidator: LoginValidator(),
            router: AuthRouter()
        )
    }

    /// ViewModel списка чатов над моками.
    static func chatListViewModel() -> ChatListViewModel {
        ChatListViewModel(
            authService: AuthServicePreviewMock(),
            sessionService: sessionService,
            conversationService: ConversationServicePreviewMock(userCache: userCache),
            conversationStorage: ConversationStorageService(container: storageContainer),
            userCache: userCache,
            realtimeService: realtimeService,
            router: ChatListRouter()
        )
    }

    /// ViewModel экрана переписки над моками. У превью собственная сессия — видно деление на входящие и исходящие.
    /// - Parameter conversation: открытая переписка; по умолчанию — групповая, с именами отправителей.
    static func chatViewModel(
        conversation: Conversation = Conversation(conversationId: 2, type: .group, memberIds: [1, 2, 3], name: "Команда", avatar: nil, opponentUserId: nil, updatedAt: Date())
    ) -> ChatViewModel {
        let user = User(userId: 1, login: "ivan", name: "Иван Петров", avatar: nil)
        let sessionService = makeSessionService(userDefaultsService: UserDefaultsServicePreviewMock(currentUser: user))
        Task { await sessionService.restore() }
        let messageService = MessageServicePreviewMock()
        let messageStorage = MessageStorageService(container: storageContainer)
        return ChatViewModel(
            conversation: conversation,
            messageService: messageService,
            messageStorage: messageStorage,
            messageSendQueue: MessageSendQueue(
                messageService: messageService,
                messageStorage: messageStorage,
                outgoingMessageStorage: OutgoingMessageStorageService(container: storageContainer),
                sessionService: sessionService,
                realtimeService: realtimeService
            ),
            sessionService: sessionService,
            userCache: userCache,
            localizationService: localizationService,
            messageTextValidator: MessageTextValidator(),
            realtimeService: realtimeService
        )
    }

    /// Сессия над заданным хранилищем настроек; при выходе очищается БД превью, а не приложения.
    /// - Parameter userDefaultsService: хранилище настроек превью.
    static func makeSessionService(userDefaultsService: UserDefaultsServiceProtocol) -> SessionService {
        SessionService(
            userDefaultsService: userDefaultsService,
            localStorageCleaner: LocalStorageCleaner(container: storageContainer)
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
            updatedAt: Date()
        )
        await sendUsersAction(for: [conversation])
        return conversation
    }

    func fetchConversations(offset: Int?, count: Int?) async throws -> ConversationsPage {
        try await Task.sleep(for: delay)
        guard offset == nil else { return ConversationsPage(conversations: [], hasNext: false) }
        let conversations = [
            Conversation(conversationId: 1, type: .single, memberIds: [1, 2], name: nil, avatar: nil, opponentUserId: 2, updatedAt: Date()),
            Conversation(conversationId: 2, type: .group, memberIds: [1, 2, 3], name: "Команда", avatar: nil, opponentUserId: nil, updatedAt: Date()),
        ]
        await sendUsersAction(for: conversations)
        return ConversationsPage(conversations: conversations, hasNext: false)
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
final class MessageServicePreviewMock: MessageServiceProtocol {
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    func fetchMessages(conversationId: Int, blockId: Int?) async throws -> MessagesPage {
        try await Task.sleep(for: delay)
        guard blockId == nil else { return MessagesPage(messages: [], nextBlockId: nil, hasNext: false) }
        let texts = ["Привет всем!", "Привет! Во сколько созвон?", "Давайте в 15:00", "Подходит", "Договорились"]
        let messages = texts.enumerated().map { index, text in
            makeMessage(id: index + 1, conversationId: conversationId, senderId: index % 3 + 1, text: text, clientId: "preview-\(index + 1)")
        }
        return MessagesPage(messages: messages.reversed(), nextBlockId: nil, hasNext: false)
    }

    func fetchBlock(blockId: Int) async throws -> [Message] {
        try await Task.sleep(for: delay)
        return []
    }

    func send(conversationId: Int, text: String, clientId: String) async throws -> Message {
        try await Task.sleep(for: delay)
        return makeMessage(id: Int.random(in: 100...10_000), conversationId: conversationId, senderId: 1, text: text, clientId: clientId)
    }

    func edit(messageId: Int, newText: String) async throws -> Message {
        try await Task.sleep(for: delay)
        return makeMessage(id: messageId, conversationId: 1, senderId: 1, text: newText)
    }

    /// Собирает текстовое сообщение, отправленное только что.
    /// - Parameters:
    ///   - id: идентификатор сообщения.
    ///   - conversationId: переписка.
    ///   - senderId: отправитель.
    ///   - text: текст.
    ///   - clientId: идентификатор клиента-отправителя; по умолчанию — новый.
    private func makeMessage(id: Int, conversationId: Int, senderId: Int, text: String, clientId: String = UUID().uuidString) -> Message {
        Message(messageId: id, clientId: clientId, conversationId: conversationId, blockId: 1, senderId: senderId, type: .text, text: text, isEdited: false, createdAt: Date(), updatedAt: Date())
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

/// Соединение с WebSocket для превью: никуда не подключается, событий не присылает.
@MainActor
final class RealtimeServicePreviewMock: RealtimeServiceProtocol {
    func start() {}

    func stop() async {}

    func events() -> AsyncStream<RealtimeEvent> {
        AsyncStream { _ in }
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
