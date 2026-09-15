//
//  UserDefaultsService.swift
//  Chatik
//

import Foundation

protocol UserDefaultsServiceProtocol: Actor {
    /// Залогиненный пользователь. `nil` — сессии нет.
    func currentUser() -> User?
    /// Сохраняет пользователя; `nil` — удаляет запись.
    func setCurrentUser(_ user: User?)
    /// Выбранный пользователем язык интерфейса. `nil` — не выбирал, используется системный.
    func language() -> AppLanguage?
    /// Сохраняет выбранный язык интерфейса.
    func setLanguage(_ language: AppLanguage)
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
    private lazy var cachedUser: User? = readUser()
    /// Кэш языка: читается из `UserDefaults` один раз при первом обращении, дальше меняется только через `setLanguage`.
    private lazy var cachedLanguage: AppLanguage? = readLanguage()

    private enum Keys {
        static let currentUser = "currentUser"
        static let language = "language"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentUser() -> User? {
        cachedUser
    }

    /// Обновляет кэш и запись в `UserDefaults`.
    /// - Parameter user: пользователь для сохранения; `nil` — удалить.
    func setCurrentUser(_ user: User?) {
        cachedUser = user
        writeUser(user)
    }

    func language() -> AppLanguage? {
        cachedLanguage
    }

    /// Обновляет кэш и запись в `UserDefaults`.
    /// - Parameter language: язык для сохранения.
    func setLanguage(_ language: AppLanguage) {
        cachedLanguage = language
        defaults.set(language.rawValue, forKey: Keys.language)
    }

    /// Читает язык из `UserDefaults`.
    private func readLanguage() -> AppLanguage? {
        defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
    }

    /// Читает и декодирует пользователя из `UserDefaults`.
    private func readUser() -> User? {
        guard let data = defaults.data(forKey: Keys.currentUser) else { return nil }
        return try? decoder.decode(User.self, from: data)
    }

    /// Записывает пользователя в `UserDefaults`; `nil` — удаляет запись.
    /// - Parameter user: пользователь для сохранения.
    private func writeUser(_ user: User?) {
        guard let user, let data = try? encoder.encode(user) else {
            defaults.removeObject(forKey: Keys.currentUser)
            return
        }
        defaults.set(data, forKey: Keys.currentUser)
    }
}
