//
//  UserDefaultsServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища настроек: держит пользователя в памяти.
actor UserDefaultsServiceMock: UserDefaultsServiceProtocol {
    private var storedUser: AuthUser?
    private var storedLanguage: AppLanguage?

    init(currentUser: AuthUser? = nil, language: AppLanguage? = nil) {
        storedUser = currentUser
        storedLanguage = language
    }

    func currentUser() -> AuthUser? {
        storedUser
    }

    func setCurrentUser(_ user: AuthUser?) {
        storedUser = user
    }

    func language() -> AppLanguage? {
        storedLanguage
    }

    func setLanguage(_ language: AppLanguage) {
        storedLanguage = language
    }
}
