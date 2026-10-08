//
//  AuthServiceObserver.swift
//  Chatik
//

import Foundation

/// Причина выхода из аккаунта.
enum LogoutReason: Equatable, Sendable {
    /// Пользователь нажал «Выйти».
    case userInitiated
    /// Сервер сообщил, что сессии больше нет: код 2003 или `null` из `/global/start`.
    case sessionExpired
}

/// Наблюдатель за выходом из аккаунта через `AuthServiceProtocol`. Подписывается через `addObserver(_:)`;
/// сервис держит наблюдателей слабо, поэтому отписываться при уничтожении не обязательно.
///
/// Выход — и по кнопке, и по истечению сессии — проходит в две фазы, и сервис дожидается каждого наблюдателя:
/// 1. `authServiceWillLogout()` — до запроса на сервер. Наблюдатель прекращает работу, которая пишет в локальную БД
///    или пользуется сессией: после выхода БД очищается, и поздняя запись досталась бы следующему пользователю.
/// 2. `authServiceDidLogout(reason:)` — после запроса, при любом его исходе: устройство разлогинено,
///    cookie сессии удалены.
///
/// Важны фазы, а не порядок подписки: все `authServiceWillLogout()` заканчиваются до запроса, все
/// `authServiceDidLogout(reason:)` начинаются после него. На порядок наблюдателей внутри одной фазы не полагайтесь.
@MainActor
protocol AuthServiceObserver: AnyObject {
    /// Выход начинается: остановить работу с сессией и дождаться записей в БД.
    func authServiceWillLogout() async
    /// Выход завершён: сессия на устройстве больше не действует.
    /// - Parameter reason: выход по кнопке или истечение сессии на сервере.
    func authServiceDidLogout(reason: LogoutReason) async
}

extension AuthServiceObserver {
    func authServiceWillLogout() async {}
    func authServiceDidLogout(reason: LogoutReason) async {}
}
