//
//  UserDefaultsService.swift
//  Chatik
//

import Foundation

protocol UserDefaultsServiceProtocol: Actor {
    /// Залогиненный пользователь. `nil` — сессии нет.
    func currentUser() -> AuthUser?
    /// Сохраняет пользователя; `nil` — удаляет запись.
    func setCurrentUser(_ user: AuthUser?)
}

/// Единственная точка доступа к `UserDefaults`. Прямое обращение к `UserDefaults` из остального кода запрещено.
///
/// Actor: всё состояние (в т.ч. кэш) изолировано, обращаться можно из любого потока через `await`.
actor UserDefaultsService: UserDefaultsServiceProtocol {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Кэш пользователя: читается из `UserDefaults` один раз при первом обращении,
    /// дальше меняется только через `setCurrentUser`, чтобы не декодировать JSON при каждом чтении.
    private lazy var cachedUser: AuthUser? = readUser()

    private enum Keys {
        static let currentUser = "currentUser"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentUser() -> AuthUser? {
        cachedUser
    }

    /// Обновляет кэш и запись в `UserDefaults`.
    /// - Parameter user: пользователь для сохранения; `nil` — удалить.
    func setCurrentUser(_ user: AuthUser?) {
        cachedUser = user
        writeUser(user)
    }

    /// Читает и декодирует пользователя из `UserDefaults`.
    private func readUser() -> AuthUser? {
        guard let data = defaults.data(forKey: Keys.currentUser) else { return nil }
        return try? decoder.decode(AuthUser.self, from: data)
    }

    /// Записывает пользователя в `UserDefaults`; `nil` — удаляет запись.
    /// - Parameter user: пользователь для сохранения.
    private func writeUser(_ user: AuthUser?) {
        guard let user, let data = try? encoder.encode(user) else {
            defaults.removeObject(forKey: Keys.currentUser)
            return
        }
        defaults.set(data, forKey: Keys.currentUser)
    }
}
