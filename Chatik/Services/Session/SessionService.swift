//
//  SessionService.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol SessionServiceProtocol: AnyObject {
    /// Залогиненный пользователь. `nil` — сессии нет (или она ещё не восстановлена, см. `isRestored`).
    var currentUser: User? { get }
    var isLoggedIn: Bool { get }
    /// `true`, когда сохранённая сессия прочитана из хранилища и `currentUser` актуален.
    var isRestored: Bool { get }
    /// `true`, если сессия была завершена сервером (код 2003), и пользователю это ещё не показано.
    var isExpired: Bool { get }

    /// Восстанавливает сессию из хранилища при старте приложения.
    func restore() async
    /// Открывает сессию после успешной регистрации / входа: очищает локальную БД и сохраняет пользователя.
    func start(user: User) async
    /// Обновляет данные текущего пользователя (например, после смены аватара). Если сессии нет — ничего не делает.
    func update(user: User) async
    /// Завершает сессию по инициативе пользователя (выход): очищает локальную БД и удаляет пользователя.
    func end() async
    /// Завершает сессию по инициативе сервера (код 2003). Если сессии нет — ничего не делает.
    func expire() async
    /// Сбрасывает признак `isExpired` после того, как пользователю показано сообщение.
    func acknowledgeExpiration()
}

/// Единая точка истины о текущей сессии. Хранит пользователя в памяти и в `UserDefaults`;
/// экраны и корневой роутер наблюдают за `currentUser`. Завершение сессии — единая точка выхода:
/// и выход пользователя, и истечение сессии на сервере очищают локальную БД.
@MainActor
@Observable
final class SessionService: SessionServiceProtocol {
    private(set) var currentUser: User?
    private(set) var isRestored = false
    private(set) var isExpired = false

    private let userDefaultsService: UserDefaultsServiceProtocol
    private let localStorageCleaner: LocalStorageCleanerProtocol

    init(userDefaultsService: UserDefaultsServiceProtocol, localStorageCleaner: LocalStorageCleanerProtocol) {
        self.userDefaultsService = userDefaultsService
        self.localStorageCleaner = localStorageCleaner
    }

    var isLoggedIn: Bool { currentUser != nil }

    /// Читает сохранённого пользователя из `UserDefaults`. Повторные вызовы ничего не делают.
    func restore() async {
        guard !isRestored else { return }
        currentUser = await userDefaultsService.currentUser()
        isRestored = true
    }

    /// Очищает локальную БД, сохраняет пользователя и открывает сессию.
    /// БД уже очищалась при завершении прошлой сессии, но при истечении сессии (2003) экраны не дожидаются
    /// своих записей в БД — запись, начатая до очистки, могла завершиться после неё. Повторная очистка при входе
    /// гарантирует, что новый пользователь не увидит данных прежнего.
    /// - Parameter user: пользователь из ответа `/auth/signup` или `/auth/login`.
    func start(user: User) async {
        await clearLocalStorage()
        currentUser = user
        isExpired = false
        await userDefaultsService.setCurrentUser(user)
    }

    /// Заменяет пользователя в памяти и `UserDefaults`, не меняя состояние сессии (`isExpired` не трогается).
    /// Без открытой сессии — no-op: обновление профиля не должно «открывать» сессию в обход `start`.
    /// - Parameter user: обновлённый пользователь из ответа `/profile/*`.
    func update(user: User) async {
        guard isLoggedIn else { return }
        currentUser = user
        await userDefaultsService.setCurrentUser(user)
    }

    /// Очищает локальную БД, затем удаляет пользователя из памяти и `UserDefaults`.
    /// БД — кэш данных этого пользователя: следующий пользователь на устройстве не должен увидеть чужие переписки.
    /// Ошибка очистки не блокирует выход, но логируется.
    func end() async {
        await clearLocalStorage()
        currentUser = nil
        await userDefaultsService.setCurrentUser(nil)
    }

    /// Завершает сессию и поднимает флаг `isExpired`, чтобы экран авторизации объяснил причину.
    /// Флаг поднимается до сброса `currentUser`: сброс переключает корневой экран на авторизацию,
    /// а `end()` содержит точку прерывания, за время которой экран уже может появиться и прочитать флаг.
    func expire() async {
        guard isLoggedIn else { return }
        isExpired = true
        await end()
    }

    func acknowledgeExpiration() {
        isExpired = false
    }

    /// Очищает локальную БД. Ошибка не блокирует ни вход, ни выход, но логируется.
    private func clearLocalStorage() async {
        do {
            try await localStorageCleaner.clearAll()
        } catch {
            Logger.storage.error("Не удалось очистить локальную БД: \(String(describing: error), privacy: .public)")
        }
    }
}
