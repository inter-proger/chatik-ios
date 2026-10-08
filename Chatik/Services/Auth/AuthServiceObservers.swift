//
//  AuthServiceObservers.swift
//  Chatik
//

import Foundation

/// Наблюдатели за выходом из аккаунта и проведение выхода в две фазы (см. `AuthServiceObserver`).
/// Общая часть `AuthService` и его мока для превью: подписка, слабые ссылки и защита от повторного выхода
/// живут в одном месте.
@MainActor
final class AuthServiceObservers {
    /// Слабая ссылка на наблюдателя: подписка не продлевает ему жизнь.
    private struct WeakObserver {
        weak var value: AuthServiceObserver?
    }

    private var observers: [WeakObserver] = []
    /// `true`, пока идёт выход: повторный выход в это время не начинается.
    private(set) var isLoggingOut = false

    /// Подписывает наблюдателя; повторная подписка того же объекта ничего не меняет.
    /// - Parameter observer: наблюдатель; хранится слабо.
    func add(_ observer: AuthServiceObserver) {
        remove(observer)
        observers.append(WeakObserver(value: observer))
    }

    /// Отписывает наблюдателя; заодно убирает ссылки на уже уничтоженных.
    /// - Parameter observer: наблюдатель, которого нужно отписать.
    func remove(_ observer: AuthServiceObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    /// Проводит выход: `authServiceWillLogout()` у всех наблюдателей → `work` → `authServiceDidLogout(reason:)`
    /// у всех наблюдателей. Каждый наблюдатель дожидается по очереди. Если выход уже идёт — ничего не делает:
    /// второй выход (повторное нажатие, 2003 от запроса, отменяемого во время выхода) уведомил бы наблюдателей дважды.
    /// - Parameters:
    ///   - reason: причина выхода — её получают наблюдатели.
    ///   - work: работа между фазами: запрос выхода, удаление cookie.
    func performLogout(reason: LogoutReason, _ work: @MainActor () async -> Void) async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }

        let observers = observers.compactMap(\.value)
        for observer in observers {
            await observer.authServiceWillLogout()
        }
        await work()
        for observer in observers {
            await observer.authServiceDidLogout(reason: reason)
        }
    }
}
