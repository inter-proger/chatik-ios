//
//  AppRouterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AppRouterTests: XCTestCase {
    private let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)
    private var realtimeService: RealtimeServiceMock!
    private var messageSendQueue: MessageSendQueueMock!
    private var conversationList: ConversationListServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        realtimeService = RealtimeServiceMock()
        messageSendQueue = MessageSendQueueMock()
        conversationList = ConversationListServiceMock()
    }

    /// Начало работы с сервером над моками списка, очереди и соединения — настоящий порядок запуска.
    private func makeSessionWork() -> SessionWorkLauncher {
        SessionWorkLauncher(conversationList: conversationList, messageNotifications: MessageNotificationServiceMock(), messageDelivery: messageSendQueue, realtimeService: realtimeService)
    }

    /// Создаёт роутер над сессией с заданным сохранённым пользователем и без задержки splash.
    private func makeSUT(
        storedUser: User? = nil,
        storedLanguage: AppLanguage? = nil,
        minimumSplashDuration: Duration = .zero
    ) -> AppRouter {
        let defaults = UserDefaultsServiceMock(currentUser: storedUser, language: storedLanguage)
        return AppRouter(
            sessionService: SessionService(userDefaultsService: defaults, localStorageCleaner: LocalStorageCleanerMock()),
            localizationService: LocalizationService(userDefaultsService: defaults, systemLanguage: .ru),
            realtimeService: realtimeService,
            sessionWork: makeSessionWork(),
            minimumSplashDuration: minimumSplashDuration
        )
    }

    /// Кейс: приложение запустилось, `restoreSession()` ещё не завершился.
    /// Ожидание: корневой экран — splash.
    func test_root_beforeRestore_isSplash() {
        let sut = makeSUT(storedUser: user)

        XCTAssertEqual(sut.root, .splash)
    }

    /// Кейс: после `restoreSession()` в хранилище нет сессии / есть сессия.
    /// Ожидание: корень — авторизация / список чатов соответственно.
    func test_restoreSession_setsRootFromStorage() async {
        let withoutSession = makeSUT()
        let withSession = makeSUT(storedUser: user)

        await withoutSession.restoreSession()
        await withSession.restoreSession()

        XCTAssertEqual(withoutSession.root, .auth)
        XCTAssertEqual(withSession.root, .chats)
    }

    /// Кейс: приложение запустилось с сохранённой сессией.
    /// Ожидание: после восстановления сессии отправка очереди запущена — один раз.
    func test_restoreSession_resumesMessageSendQueue() async {
        let sut = makeSUT(storedUser: user)

        await sut.restoreSession()

        XCTAssertEqual(messageSendQueue.resumeCallCount, 1)
    }

    /// Кейс: приложение запустилось с сохранённой сессией.
    /// Ожидание: порядок запуска — список переписок, отправка очереди, соединение: ответ на отправку поднимает
    /// переписку в списке, а очередь событий не хранит события для будущих подписчиков, и `connected` не должен
    /// пройти мимо них.
    func test_restoreSession_startsListThenSendQueueThenRealtime() async {
        let sut = makeSUT(storedUser: user)
        var calls: [String] = []
        conversationList.onStart = { calls.append("list") }
        messageSendQueue.onResume = { calls.append("sendQueue") }
        realtimeService.onStart = { calls.append("realtime") }

        await sut.restoreSession()

        XCTAssertEqual(calls, ["list", "sendQueue", "realtime"])
    }

    /// Кейс: задано минимальное время показа splash, сессия восстанавливается мгновенно.
    /// Ожидание: `restoreSession()` завершается не раньше этого времени; до завершения корень — splash.
    func test_restoreSession_holdsSplashForMinimumDuration() async {
        let sut = makeSUT(minimumSplashDuration: .milliseconds(150))
        let start = ContinuousClock.now

        await sut.restoreSession()

        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(150))
        XCTAssertEqual(sut.root, .auth)
    }

    /// Кейс: сессия открывается, завершается пользователем, открывается и истекает по 2003.
    /// Ожидание: корень следует за состоянием сессии: auth → chats → auth → chats → auth.
    func test_root_followsSessionChanges() async {
        let defaults = UserDefaultsServiceMock()
        let session = SessionService(userDefaultsService: defaults, localStorageCleaner: LocalStorageCleanerMock())
        let sut = AppRouter(
            sessionService: session,
            localizationService: LocalizationService(userDefaultsService: defaults, systemLanguage: .ru),
            realtimeService: realtimeService,
            sessionWork: makeSessionWork(),
            minimumSplashDuration: .zero
        )
        await sut.restoreSession()

        await session.start(user: user)
        XCTAssertEqual(sut.root, .chats)

        await session.end()
        XCTAssertEqual(sut.root, .auth)

        await session.start(user: user)
        XCTAssertEqual(sut.root, .chats)

        await session.expire()
        XCTAssertEqual(sut.root, .auth)
    }

    /// Кейс: пользователь ранее выбрал английский; системный язык — русский.
    /// Ожидание: после `restoreSession()` локаль приложения — английская.
    func test_restoreSession_restoresSavedLanguage() async {
        let sut = makeSUT(storedLanguage: .en)
        XCTAssertEqual(sut.locale.identifier, "ru")

        await sut.restoreSession()

        XCTAssertEqual(sut.locale.identifier, "en")
    }

    // MARK: - WebSocket

    /// Кейс: приложение запустилось, сессия восстановлена.
    /// Ожидание: работа с сервером начата (`/global/start`) — ровно один раз.
    func test_restoreSession_startsRealtime() async {
        let sut = makeSUT(storedUser: user)

        await sut.restoreSession()

        XCTAssertEqual(realtimeService.calls, ["start"])
    }

    /// Кейс: приложение ушло в фон и вернулось; между ними — повторные переходы в то же состояние.
    /// Ожидание: уход в фон закрывает соединение, возврат открывает заново; повторы ничего не делают.
    func test_scenePhase_backgroundStopsAndForegroundStarts() async {
        let sut = makeSUT(storedUser: user)
        await sut.restoreSession()

        await sut.didChangeScenePhase(isActive: false)
        await sut.didChangeScenePhase(isActive: false)
        await sut.didChangeScenePhase(isActive: true)
        await sut.didChangeScenePhase(isActive: true)

        XCTAssertEqual(realtimeService.calls, ["start", "stop", "start"])
    }

    /// Кейс: приложение стало активным, не побывав в фоне (запуск, закрытие шторки).
    /// Ожидание: соединение не перезапускается.
    func test_scenePhase_activeWithoutBackground_doesNothing() async {
        let sut = makeSUT(storedUser: user)
        await sut.restoreSession()

        await sut.didChangeScenePhase(isActive: true)

        XCTAssertEqual(realtimeService.calls, ["start"])
    }

    // MARK: - Debug-вход

    /// Создаёт роутер с debug-входом над сессией с заданным сохранённым пользователем.
    /// - Parameters:
    ///   - arguments: разобранные аргументы запуска.
    ///   - service: мок debug-входа.
    ///   - storedUser: пользователь, залогиненный до запуска.
    private func makeDebugSUT(
        arguments: Result<DebugLoginCredentials, DebugLaunchArgumentsError>,
        service: DebugLoginServiceMock,
        storedUser: User? = nil
    ) -> AppRouter {
        let defaults = UserDefaultsServiceMock(currentUser: storedUser)
        return AppRouter(
            sessionService: SessionService(userDefaultsService: defaults, localStorageCleaner: LocalStorageCleanerMock()),
            localizationService: LocalizationService(userDefaultsService: defaults, systemLanguage: .ru),
            realtimeService: realtimeService,
            sessionWork: makeSessionWork(),
            debugLoginLaunch: DebugLoginLaunch(arguments: arguments, service: service),
            minimumSplashDuration: .zero
        )
    }

    /// Кейс: роутер с debug-входом создан, `restoreSession()` ещё не вызван.
    /// Ожидание: корень — стартовый экран debug-входа с логином, а не splash.
    func test_debugLogin_beforeRestore_isDebugLoginRoot() {
        let sut = makeDebugSUT(arguments: .success(DebugLoginCredentials(login: "anna", password: "p")), service: DebugLoginServiceMock())

        XCTAssertEqual(sut.root, .debugLogin)
        XCTAssertEqual(sut.debugLoginState, .inProgress(login: "anna"))
    }

    /// Кейс: debug-вход выполняется, затем завершается успешно.
    /// Ожидание: во время входа корень — `.debugLogin`, сервис получил данные из аргументов; после — корень выводится
    /// из сессии, работу с сервером роутер сам не начинает (её начинает сервис).
    func test_debugLogin_success_finishesDebugScenario() async {
        let credentials = DebugLoginCredentials(login: "anna", password: "p")
        let service = DebugLoginServiceMock()
        let sut = makeDebugSUT(arguments: .success(credentials), service: service, storedUser: user)
        var rootDuringLogin: AppRoot?
        service.onLogin = { rootDuringLogin = sut.root }

        await sut.restoreSession()

        XCTAssertEqual(rootDuringLogin, .debugLogin)
        XCTAssertEqual(service.receivedCredentials, [credentials])
        XCTAssertNil(sut.debugLoginState)
        XCTAssertEqual(sut.root, .chats)
        XCTAssertEqual(realtimeService.calls, [])
        XCTAssertEqual(messageSendQueue.resumeCallCount, 0)
    }

    /// Кейс: debug-вход вернул ошибку неверного пароля; затем нажата «Продолжить без debug-входа».
    /// Ожидание: корень `.debugLogin` с текстом ошибки; после нажатия — экран авторизации, работа с сервером не начата.
    func test_debugLogin_failure_showsErrorThenSkipOpensAuth() async {
        let service = DebugLoginServiceMock()
        service.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.invalidPassword))
        let sut = makeDebugSUT(arguments: .success(DebugLoginCredentials(login: "anna", password: "p")), service: service)

        await sut.restoreSession()

        XCTAssertEqual(sut.root, .debugLogin)
        XCTAssertEqual(sut.debugLoginState, .failed(message: CommonStrings.errorInvalidPassword))

        sut.didTapSkipDebugLogin()

        XCTAssertEqual(sut.root, .auth)
        XCTAssertEqual(realtimeService.calls, [])
    }

    /// Кейс: передан только `-debugPassword`, на устройстве сохранена сессия; затем нажата «Продолжить без debug-входа».
    /// Ожидание: сервис не вызван, показана ошибка разбора; после нажатия — список чатов и работа с сервером, как при
    /// обычном старте.
    func test_debugLogin_argumentsError_showsErrorThenSkipStartsRegularSession() async {
        let service = DebugLoginServiceMock()
        let sut = makeDebugSUT(arguments: .failure(.missingLogin), service: service, storedUser: user)
        XCTAssertEqual(sut.debugLoginState, .inProgress(login: nil))

        await sut.restoreSession()

        XCTAssertEqual(service.receivedCredentials, [])
        XCTAssertEqual(sut.debugLoginState, .failed(message: DebugLoginStrings.errorMissingLogin))
        XCTAssertEqual(realtimeService.calls, [])

        sut.didTapSkipDebugLogin()

        XCTAssertEqual(sut.root, .chats)
        XCTAssertEqual(realtimeService.calls, ["start"])
        XCTAssertEqual(messageSendQueue.resumeCallCount, 1)
    }

    /// Кейс: «Продолжить без debug-входа» нажата, пока вход ещё идёт.
    /// Ожидание: нажатие игнорируется — корень остаётся `.debugLogin`.
    func test_debugLogin_skipDuringLogin_isIgnored() async {
        let service = DebugLoginServiceMock()
        let sut = makeDebugSUT(arguments: .success(DebugLoginCredentials(login: "anna", password: "p")), service: service)
        var rootAfterSkip: AppRoot?
        service.onLogin = {
            sut.didTapSkipDebugLogin()
            rootAfterSkip = sut.root
        }

        await sut.restoreSession()

        XCTAssertEqual(rootAfterSkip, .debugLogin)
    }

    /// Кейс: во время debug-входа приложение уходит в фон и возвращается.
    /// Ожидание: соединение не трогается — ни остановки, ни запуска; после входа приложение активно, закрывать нечего.
    func test_debugLogin_scenePhaseDuringLogin_isIgnored() async {
        let service = DebugLoginServiceMock()
        let sut = makeDebugSUT(arguments: .success(DebugLoginCredentials(login: "anna", password: "p")), service: service)
        service.onLogin = {
            await sut.didChangeScenePhase(isActive: false)
            await sut.didChangeScenePhase(isActive: true)
        }

        await sut.restoreSession()

        XCTAssertEqual(realtimeService.calls, [])
    }

    /// Кейс: приложение ушло в фон во время debug-входа, вход завершился в фоне, затем приложение вернулось.
    /// Ожидание: после входа соединение закрывается, как при уходе в фон; возврат открывает его заново.
    func test_debugLogin_finishedInBackground_stopsRealtimeUntilForeground() async {
        let service = DebugLoginServiceMock()
        let sut = makeDebugSUT(arguments: .success(DebugLoginCredentials(login: "anna", password: "p")), service: service)
        service.onLogin = { await sut.didChangeScenePhase(isActive: false) }

        await sut.restoreSession()
        XCTAssertEqual(realtimeService.calls, ["stop"])

        await sut.didChangeScenePhase(isActive: true)

        XCTAssertEqual(realtimeService.calls, ["stop", "start"])
    }

    /// Кейс: экран ошибки разбора аргументов при сохранённой сессии; приложение уходит в фон и возвращается, затем
    /// нажата «Продолжить без debug-входа».
    /// Ожидание: пока показан экран ошибки, соединение не трогается; после нажатия работа с сервером начинается в обычном
    /// порядке — список, очередь, соединение.
    func test_debugLogin_scenePhaseOnFailureScreen_isIgnoredUntilSkip() async {
        let sut = makeDebugSUT(arguments: .failure(.missingLogin), service: DebugLoginServiceMock(), storedUser: user)
        var calls: [String] = []
        conversationList.onStart = { calls.append("list") }
        messageSendQueue.onResume = { calls.append("sendQueue") }
        realtimeService.onStart = { calls.append("realtime") }
        await sut.restoreSession()

        await sut.didChangeScenePhase(isActive: false)
        await sut.didChangeScenePhase(isActive: true)
        XCTAssertEqual(realtimeService.calls, [])

        sut.didTapSkipDebugLogin()

        XCTAssertEqual(calls, ["list", "sendQueue", "realtime"])
    }
}
