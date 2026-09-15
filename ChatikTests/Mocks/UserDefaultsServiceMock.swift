//
//  UserDefaultsServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища настроек: держит пользователя в памяти.
actor UserDefaultsServiceMock: UserDefaultsServiceProtocol {
    private var storedUser: User?
    private var storedLanguage: AppLanguage?

    init(currentUser: User? = nil, language: AppLanguage? = nil) {
        storedUser = currentUser
        storedLanguage = language
    }

    func currentUser() -> User? {
        storedUser
    }

    func setCurrentUser(_ user: User?) {
        storedUser = user
    }

    func language() -> AppLanguage? {
        storedLanguage
    }

    func setLanguage(_ language: AppLanguage) {
        storedLanguage = language
    }
}
