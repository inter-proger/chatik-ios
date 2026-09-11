//
//  AuthViewModelTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func makeSUT(mode: AuthMode = .signup) -> AuthViewModel {
        AuthViewModel(mode: mode, authService: AuthService(networkService: NetworkServiceMock()), router: AuthRouter())
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
}
