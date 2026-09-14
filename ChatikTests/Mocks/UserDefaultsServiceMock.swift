//
//  UserDefaultsServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища настроек: держит пользователя в памяти.
actor UserDefaultsServiceMock: UserDefaultsServiceProtocol {
    private var storedUser: AuthUser?

    init(currentUser: AuthUser? = nil) {
        storedUser = currentUser
    }

    func currentUser() -> AuthUser? {
        storedUser
    }

    func setCurrentUser(_ user: AuthUser?) {
        storedUser = user
    }
}
