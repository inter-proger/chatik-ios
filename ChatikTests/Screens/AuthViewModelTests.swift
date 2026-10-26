//
//  AuthViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AuthViewModelTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var userDefaultsService: UserDefaultsServiceMock!
    private var sessionService: SessionService!
    private var localizationService: LocalizationService!
    private var realtimeService: RealtimeServiceMock!
    private var messageSendQueue: MessageSendQueueMock!
    private var conversationList: ConversationListServiceMock!
    private var notifications: InAppNotificationServiceMock!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        userDefaultsService = UserDefaultsServiceMock()
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        localizationService = LocalizationService(userDefaultsService: userDefaultsService, systemLanguage: .ru)
        realtimeService = RealtimeServiceMock()
        messageSendQueue = MessageSendQueueMock()
        conversationList = ConversationListServiceMock()
        notifications = InAppNotificationServiceMock()
    }

    private func makeSUT(mode: AuthMode = .signup, authService: AuthServiceProtocol? = nil) -> AuthViewModel {
        AuthViewModel(
            mode: mode,
            authService: authService ?? AuthService(networkService: networkService),
            sessionService: sessionService,
            sessionWork: SessionWorkLauncher(
                conversationList: conversationList,
                messageNotifications: MessageNotificationServiceMock(),
                memberReads: MemberReadServiceMock(),
                groupInfo: GroupInfoServiceMock(),
                messageDelivery: messageSendQueue,
                realtimeService: realtimeService
            ),
            localizationService: localizationService,
            signupValidator: SignupValidator(),
            loginValidator: LoginValidator(),
            notifications: notifications,
            router: AuthRouter()
        )
    }

    /// Текст markdown-шаблона без разметки и с подставленным служебным URL — то, что увидит пользователь.
    private func plainText(of format: String) -> String {
        let markdown = String(format: format, AuthViewModel.switchModeURL.absoluteString)
        return String((try? AttributedString(markdown: markdown))?.characters ?? AttributedString(markdown).characters)
    }

    /// Заполняет форму валидными для регистрации данными.
    private func fillValidSignupForm(_ sut: AuthViewModel) {
        sut.name = "Иван"
        sut.login = "ivan"
        sut.password = "Password1"
    }

    /// Кейс: ViewModel создана без явного режима.
    /// Ожидание: режим — регистрация; заголовок, кнопка и текст переключения — для регистрации.
    func test_initialMode_isSignupByDefault() {
        let sut = makeSUT()

        XCTAssertTrue(sut.isSignup)
        XCTAssertEqual(sut.title, AuthStrings.titleSignup)
        XCTAssertEqual(sut.primaryButtonTitle, AuthStrings.buttonSignup)
        XCTAssertEqual(String(sut.switchModeText.characters), plainText(of: AuthStrings.switchToLoginFormat))
    }

    /// Кейс: ViewModel создана в режиме входа.
    /// Ожидание: заголовок, кнопка и текст переключения — для входа.
    func test_loginMode_exposesLoginTexts() {
        let sut = makeSUT(mode: .login)

        XCTAssertFalse(sut.isSignup)
        XCTAssertEqual(sut.title, AuthStrings.titleLogin)
        XCTAssertEqual(sut.primaryButtonTitle, AuthStrings.buttonLogin)
        XCTAssertEqual(String(sut.switchModeText.characters), plainText(of: AuthStrings.switchToSignupFormat))
    }

    /// Кейс: пользователь дважды нажимает ссылку переключения режима.
    /// Ожидание: регистрация → вход → регистрация.
    func test_switchMode_togglesBetweenSignupAndLogin() {
        let sut = makeSUT()

        sut.switchMode()
        XCTAssertFalse(sut.isSignup)

        sut.switchMode()
        XCTAssertTrue(sut.isSignup)
    }

    /// Кейс: пользователь дважды нажимает «глаз» у поля пароля.
    /// Ожидание: скрыт → показан → скрыт.
    func test_togglePasswordVisibility_flipsFlag() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isPasswordVisible)

        sut.togglePasswordVisibility()
        XCTAssertTrue(sut.isPasswordVisible)

        sut.togglePasswordVisibility()
        XCTAssertFalse(sut.isPasswordVisible)
    }

    /// Кейс: текст переключения режима собран из markdown-шаблона.
    /// Ожидание: в тексте ровно одна ссылка — служебный URL переключения режима.
    func test_switchModeText_containsSwitchModeLink() {
        let sut = makeSUT()

        let links = sut.switchModeText.runs.compactMap(\.link)

        XCTAssertEqual(links, [AuthViewModel.switchModeURL])
    }

    /// Кейс: текст соглашения собран из markdown-шаблона.
    /// Ожидание: ссылки в порядке следования — лицензионное соглашение, политика конфиденциальности.
    func test_agreementText_containsLicenseAndPrivacyLinks() {
        let sut = makeSUT()

        let links = sut.agreementText.runs.compactMap(\.link)

        XCTAssertEqual(links, [AppConfig.licenseAgreementURL, AppConfig.privacyPolicyURL])
    }

    // MARK: - Кнопка

    /// Кейс: режим регистрации, форма пустая → заполнена валидно → одно поле испорчено.
    /// Ожидание: кнопка неактивна → активна → снова неактивна.
    func test_isPrimaryButtonEnabled_signup_followsFormValidity() {
        let sut = makeSUT(mode: .signup)
        XCTAssertFalse(sut.isPrimaryButtonEnabled)

        fillValidSignupForm(sut)
        XCTAssertTrue(sut.isPrimaryButtonEnabled)

        sut.login = "иван"
        XCTAssertFalse(sut.isPrimaryButtonEnabled)
    }

    /// Кейс: режим входа; логин / пароль пустые, из пробелов, произвольные непустые.
    /// Ожидание: кнопка активна только при обоих непустых полях; формат не проверяется.
    func test_isPrimaryButtonEnabled_login_requiresNonBlankLoginAndPassword() {
        let sut = makeSUT(mode: .login)
        XCTAssertFalse(sut.isPrimaryButtonEnabled)

        sut.login = "иван"
        sut.password = "   "
        XCTAssertFalse(sut.isPrimaryButtonEnabled)

        sut.password = "1"
        XCTAssertTrue(sut.isPrimaryButtonEnabled)
    }

    // MARK: - Состояние полей

    /// Кейс: режим регистрации, поле логина получило фокус (содержимое любое).
    /// Ожидание: под полем подсказка о требованиях, без подсветки ошибки.
    func test_fieldState_focused_showsHintWithoutError() {
        let sut = makeSUT(mode: .signup)
        sut.login = "иван"
        sut.focusedField = .login

        XCTAssertEqual(sut.loginFieldState, AuthFieldState(message: AuthStrings.hintLogin, isError: false))
    }

    /// Кейс: режим регистрации, фокус ушёл с поля с непустым невалидным значением.
    /// Ожидание: подсветка ошибки и текст, что нужно исправить.
    func test_fieldState_unfocusedInvalid_showsError() {
        let sut = makeSUT(mode: .signup)
        sut.password = "password"
        sut.focusedField = nil

        XCTAssertEqual(
            sut.passwordFieldState,
            AuthFieldState(message: AuthStrings.errorPasswordMissingUppercase, isError: true)
        )
    }

    /// Кейс: режим регистрации, поле без фокуса пустое (ещё не заполняли) или валидное.
    /// Ожидание: ни подсказки, ни ошибки.
    func test_fieldState_unfocusedEmptyOrValid_isEmpty() {
        let sut = makeSUT(mode: .signup)

        XCTAssertEqual(sut.nameFieldState, .empty)

        sut.name = "Иван"
        XCTAssertEqual(sut.nameFieldState, .empty)
    }

    /// Кейс: режим входа, поле в фокусе или содержит невалидные для регистрации данные.
    /// Ожидание: подсказки и ошибки не показываются — в режиме входа валидации нет.
    func test_fieldState_loginMode_neverShowsHintsOrErrors() {
        let sut = makeSUT(mode: .login)
        sut.login = "иван!"
        sut.password = "x"

        sut.focusedField = .login
        XCTAssertEqual(sut.loginFieldState, .empty)

        sut.focusedField = nil
        XCTAssertEqual(sut.loginFieldState, .empty)
        XCTAssertEqual(sut.passwordFieldState, .empty)
    }

    // MARK: - Отправка формы

    /// Кейс: режим регистрации, сервер вернул пользователя.
    /// Ожидание: отправлен запрос на /auth/signup, сессия открыта, пользователь сохранён в `UserDefaults`.
    func test_submit_signupSuccess_startsSession() async {
        let user = User(userId: 7, login: "ivan", name: "Иван", avatar: nil)
        networkService.stubbedResult = .success(user)
        let sut = makeSUT(mode: .signup)
        fillValidSignupForm(sut)

        await sut.performAuthentication()

        let stored = await userDefaultsService.currentUser()
        XCTAssertEqual(networkService.requestedEndpoints.first?.path, "/auth/signup")
        XCTAssertEqual(sessionService.currentUser, user)
        XCTAssertEqual(stored, user)
        XCTAssertEqual(notifications.shownErrors, [])
        XCTAssertFalse(sut.isLoading)
    }

    /// Кейс: режим входа, сервер вернул пользователя.
    /// Ожидание: отправлен запрос на /auth/login, сессия открыта.
    func test_submit_loginSuccess_startsSession() async {
        let user = User(userId: 7, login: "ivan", name: "Иван", avatar: nil)
        networkService.stubbedResult = .success(user)
        let sut = makeSUT(mode: .login)
        sut.login = "ivan"
        sut.password = "secret"

        await sut.performAuthentication()

        XCTAssertEqual(networkService.requestedEndpoints.first?.path, "/auth/login")
        XCTAssertEqual(sessionService.currentUser, user)
    }

    /// Кейс: вход успешен.
    /// Ожидание: после открытия сессии работа с сервером начата заново — WebSocket подключится под новым пользователем.
    func test_submit_success_startsRealtime() async {
        networkService.stubbedResult = .success(User(userId: 7, login: "ivan", name: "Иван", avatar: nil))
        let sut = makeSUT(mode: .login)
        sut.login = "ivan"
        sut.password = "secret"

        await sut.performAuthentication()

        XCTAssertEqual(realtimeService.startCallCount, 1)
    }

    /// Кейс: вход не удался.
    /// Ожидание: ни WebSocket, ни отправка очереди не запускаются.
    func test_submit_failure_doesNotStartRealtime() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.wrongCredentials))
        let sut = makeSUT(mode: .login)
        sut.login = "ivan"
        sut.password = "secret"

        await sut.performAuthentication()

        XCTAssertEqual(realtimeService.startCallCount, 0)
        XCTAssertEqual(messageSendQueue.resumeCallCount, 0)
    }

    /// Кейс: вход успешен.
    /// Ожидание: отправка очереди запущена после открытия сессии и до соединения с WebSocket — сообщения,
    /// прерванные прошлой сессией, уходят под новым пользователем.
    func test_submit_success_resumesSendQueueAfterSessionBeforeRealtime() async {
        networkService.stubbedResult = .success(User(userId: 7, login: "ivan", name: "Иван", avatar: nil))
        let sut = makeSUT(mode: .login)
        sut.login = "ivan"
        sut.password = "secret"
        var calls: [String] = []
        messageSendQueue.onResume = { [unowned self] in calls.append("sendQueue, loggedIn=\(sessionService.isLoggedIn)") }
        realtimeService.onStart = { calls.append("realtime") }

        await sut.performAuthentication()

        XCTAssertEqual(calls, ["sendQueue, loggedIn=true", "realtime"])
    }

    /// Кейс: логин и имя введены с краевыми пробелами, пароль — с пробелом в начале.
    /// Ожидание: в запрос уходят логин и имя без краевых пробелов, пароль — без изменений.
    func test_submit_trimsLoginAndName_keepsPassword() async throws {
        networkService.stubbedResult = .success(User(userId: 7, login: "ivan", name: "Иван", avatar: nil))
        let sut = makeSUT(mode: .signup)
        sut.name = " Иван "
        sut.login = " ivan "
        sut.password = " Password1"

        await sut.performAuthentication()

        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.parameters, ["login": "ivan", "password": " Password1", "name": "Иван"])
    }

    /// Кейс: сервер ответил ошибкой API (неверные учётные данные).
    /// Ожидание: показано соответствующее сообщение, сессия не открыта.
    func test_submit_apiError_showsMessageAndKeepsSessionClosed() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.wrongCredentials))
        let sut = makeSUT(mode: .login)
        sut.login = "ivan"
        sut.password = "wrong"

        await sut.performAuthentication()

        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorWrongCredentials])
        XCTAssertFalse(sessionService.isLoggedIn)
        XCTAssertFalse(sut.isLoading)
    }

    /// Кейс: запрос выполняется (`isLoading == true`) при валидной форме.
    /// Ожидание: во время запроса `isLoading == true` и кнопка неактивна; после — `isLoading == false`.
    func test_isPrimaryButtonEnabled_whileLoading_isFalse() async {
        let authService = AuthServiceMock()
        authService.stubbedUser = .success(User(userId: 1, login: "ivan", name: "Иван", avatar: nil))
        let sut = makeSUT(mode: .signup, authService: authService)
        fillValidSignupForm(sut)
        XCTAssertTrue(sut.isPrimaryButtonEnabled)

        var stateDuringRequest: (isLoading: Bool, isEnabled: Bool)?
        authService.onRequest = { stateDuringRequest = (sut.isLoading, sut.isPrimaryButtonEnabled) }

        await sut.performAuthentication()

        XCTAssertEqual(stateDuringRequest?.isLoading, true)
        XCTAssertEqual(stateDuringRequest?.isEnabled, false)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Истечение сессии

    /// Кейс: экран появился после того, как сервер завершил сессию (код 2003), приложение активно.
    /// Ожидание: показано сообщение «сессия истекла», флаг в сессии сброшен — повторный вызов ничего не показывает.
    func test_showExpirationIfNeeded_afterExpiration_showsMessageOnce() async {
        await sessionService.start(user: User(userId: 1, login: "ivan", name: "Иван", avatar: nil))
        await sessionService.expire()
        let sut = makeSUT(mode: .login)

        sut.showExpirationIfNeeded()
        sut.showExpirationIfNeeded()

        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorUnauthorized])
        XCTAssertFalse(sessionService.isExpired)
    }

    /// Кейс: сессия истекла, пока приложение неактивно; затем приложение снова активно.
    /// Ожидание: в неактивном приложении сообщение отброшено и истечение не отмечено просмотренным; после
    /// возврата сообщение показано и истечение отмечено.
    func test_showExpirationIfNeeded_whileInactive_showsAfterActivation() async {
        await sessionService.start(user: User(userId: 1, login: "ivan", name: "Иван", avatar: nil))
        await sessionService.expire()
        notifications.isActive = false
        let sut = makeSUT(mode: .login)

        sut.showExpirationIfNeeded()
        XCTAssertEqual(notifications.shownErrors, [])
        XCTAssertTrue(sessionService.isExpired)
        notifications.isActive = true
        sut.showExpirationIfNeeded()

        XCTAssertEqual(notifications.shownErrors, [CommonStrings.errorUnauthorized])
        XCTAssertFalse(sessionService.isExpired)
    }

    /// Кейс: экран появился при обычном старте или после явного выхода.
    /// Ожидание: сообщений нет.
    func test_showExpirationIfNeeded_withoutExpiration_showsNothing() {
        let sut = makeSUT(mode: .login)

        sut.showExpirationIfNeeded()

        XCTAssertEqual(notifications.shownErrors, [])
    }

    // MARK: - Язык

    /// Кейс: пользователь выбрал английский в меню языков.
    /// Ожидание: язык сервиса переключён, выбор сохранён в `UserDefaults`, тексты экрана — на английском.
    func test_selectLanguage_appliesAndPersistsLanguage() async {
        let sut = makeSUT(mode: .login)
        XCTAssertEqual(sut.language, .ru)

        sut.selectLanguage(.en)
        await Task.yield()
        await waitUntil { self.localizationService.language == .en }

        let stored = await userDefaultsService.language()
        XCTAssertEqual(sut.language, .en)
        XCTAssertEqual(stored, .en)
    }

    /// Ждёт выполнения условия, давая отработать задачам, запущенным через `Task {}`.
    private func waitUntil(timeout: Duration = .seconds(1), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
