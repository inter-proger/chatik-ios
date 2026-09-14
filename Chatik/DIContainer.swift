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
    let userDefaultsService: UserDefaultsServiceProtocol
    let sessionService: SessionServiceProtocol
    let localizationService: LocalizationServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol

    private init() {
        let userDefaultsService = UserDefaultsService()
        let sessionService = SessionService(userDefaultsService: userDefaultsService)
        // Код 2003 от любого запроса завершает сессию — приложение само переключится на экран авторизации.
        let networkService = NetworkService(onUnauthorized: {
            Task { @MainActor in await sessionService.expire() }
        })
        self.userDefaultsService = userDefaultsService
        self.sessionService = sessionService
        self.localizationService = LocalizationService(userDefaultsService: userDefaultsService)
        self.networkService = networkService
        self.authService = AuthService(networkService: networkService)
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
    }
}
