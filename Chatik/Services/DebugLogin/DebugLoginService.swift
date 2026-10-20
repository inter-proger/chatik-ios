//
//  DebugLoginService.swift
//  Chatik
//

#if DEBUG
import Foundation

/// Debug-вход по аргументам запуска — всё, что о нём знает `AppRouter`.
@MainActor
protocol DebugLoginPerforming: AnyObject {
    /// Разлогинивает текущего пользователя, если он есть, входит под переданным, открывает сессию
    /// и начинает работу с сервером. Сессия должна быть восстановлена (`SessionService.restore()`).
    /// - Parameter credentials: логин и пароль из аргументов запуска.
    /// - Throws: ошибка входа; пользователь в этом случае разлогинен.
    func login(_ credentials: DebugLoginCredentials) async throws
}

/// Запуск по debug-сценарию: разобранные аргументы и сервис, который выполнит вход.
struct DebugLoginLaunch {
    /// Данные для входа или ошибка разбора аргументов — её покажет стартовый экран.
    let arguments: Result<DebugLoginCredentials, DebugLaunchArgumentsError>
    let service: DebugLoginPerforming
}

/// Debug-вход повторяет обычный путь, а не обходит его: выход — как по кнопке «Выйти», вход — как
/// с экрана авторизации. Очистка БД, загрузка черновиков и очереди отправки, подписки на выход работают без изменений.
@MainActor
final class DebugLoginService: DebugLoginPerforming {
    private let authService: AuthServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let sessionWork: SessionWorkStarting

    /// - Parameters:
    ///   - authService: выход прежнего пользователя и вход нового.
    ///   - sessionService: состояние сессии и её открытие после входа.
    ///   - sessionWork: начало работы с сервером после открытия сессии.
    init(authService: AuthServiceProtocol, sessionService: SessionServiceProtocol, sessionWork: SessionWorkStarting) {
        self.authService = authService
        self.sessionService = sessionService
        self.sessionWork = sessionWork
    }

    /// Выход залогиненного пользователя (любого, в том числе того же) → вход → открытие сессии → работа с сервером.
    /// Черновики и очередь отправки переживают выход и вернутся, если вошли тем же пользователем.
    /// - Parameter credentials: логин и пароль из аргументов запуска.
    func login(_ credentials: DebugLoginCredentials) async throws {
        if sessionService.isLoggedIn {
            await authService.logout()
        }
        let user = try await authService.login(login: credentials.login, password: credentials.password)
        await sessionService.start(user: user)
        sessionWork.startSessionWork()
    }
}
#endif
