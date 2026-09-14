//
//  AuthViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func makeSUT(mode: AuthMode = .signup) -> AuthViewModel {
        AuthViewModel(
            mode: mode,
            authService: AuthService(networkService: NetworkServiceMock()),
            signupValidator: SignupValidator(),
            loginValidator: LoginValidator(),
            router: AuthRouter()
        )
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
        XCTAssertEqual(String(sut.switchModeText.characters), "Уже зарегистрированы? Войти")
    }

    /// Кейс: ViewModel создана в режиме входа.
    /// Ожидание: заголовок, кнопка и текст переключения — для входа.
    func test_loginMode_exposesLoginTexts() {
        let sut = makeSUT(mode: .login)

        XCTAssertFalse(sut.isSignup)
        XCTAssertEqual(sut.title, AuthStrings.titleLogin)
        XCTAssertEqual(sut.primaryButtonTitle, AuthStrings.buttonLogin)
        XCTAssertEqual(String(sut.switchModeText.characters), "Нет аккаунта? Зарегистрироваться")
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
}
