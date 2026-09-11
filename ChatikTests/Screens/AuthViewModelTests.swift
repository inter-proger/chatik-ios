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

    func test_initialMode_isSignupByDefault() {
        let sut = makeSUT()

        XCTAssertTrue(sut.isSignup)
        XCTAssertEqual(sut.title, AuthStrings.titleSignup)
        XCTAssertEqual(sut.primaryButtonTitle, AuthStrings.buttonSignup)
        XCTAssertEqual(String(sut.switchModeText.characters), "Уже зарегистрированы? Войти")
    }

    func test_loginMode_exposesLoginTexts() {
        let sut = makeSUT(mode: .login)

        XCTAssertFalse(sut.isSignup)
        XCTAssertEqual(sut.title, AuthStrings.titleLogin)
        XCTAssertEqual(sut.primaryButtonTitle, AuthStrings.buttonLogin)
        XCTAssertEqual(String(sut.switchModeText.characters), "Нет аккаунта? Зарегистрироваться")
    }

    func test_switchMode_togglesBetweenSignupAndLogin() {
        let sut = makeSUT()

        sut.switchMode()
        XCTAssertFalse(sut.isSignup)

        sut.switchMode()
        XCTAssertTrue(sut.isSignup)
    }

    func test_togglePasswordVisibility_flipsFlag() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isPasswordVisible)

        sut.togglePasswordVisibility()
        XCTAssertTrue(sut.isPasswordVisible)

        sut.togglePasswordVisibility()
        XCTAssertFalse(sut.isPasswordVisible)
    }

    func test_switchModeText_containsSwitchModeLink() {
        let sut = makeSUT()

        let links = sut.switchModeText.runs.compactMap(\.link)

        XCTAssertEqual(links, [AuthViewModel.switchModeURL])
    }

    func test_agreementText_containsLicenseAndPrivacyLinks() {
        let sut = makeSUT()

        let links = sut.agreementText.runs.compactMap(\.link)

        XCTAssertEqual(links, [AppConfig.licenseAgreementURL, AppConfig.privacyPolicyURL])
    }
}
