//
//  DIContainer.swift
//  Chatik
//

import Foundation

/// Единая точка сборки общих сервисов приложения.
final class DIContainer {
    static let shared = DIContainer()

    let networkService: NetworkServiceProtocol
    let authService: AuthServiceProtocol
    let signupValidator: SignupValidatorProtocol
    let loginValidator: LoginValidatorProtocol

    private init() {
        let networkService = NetworkService()
        self.networkService = networkService
        self.authService = AuthService(networkService: networkService)
        self.signupValidator = SignupValidator()
        self.loginValidator = LoginValidator()
    }
}
