//
//  AppRouter.swift
//  Chatik
//

import Foundation

/// Корневой экран приложения.
enum AppRoot: Equatable {
    /// Splash-экран: сессия читается из хранилища.
    case splash
    #if DEBUG
    /// Стартовый экран debug-входа по аргументам запуска.
    case debugLogin
    #endif
    case auth
    case chats
}

#if DEBUG
/// Состояние debug-входа по аргументам запуска.
enum DebugLoginState: Equatable {
    /// Вход идёт; `login` — `nil`, пока не ясно, верны ли аргументы.
    case inProgress(login: String?)
    /// Вход не удался; `message` — текст для экрана.
    case failed(message: String)
}
#endif

/// Роутер уровня приложения: корневой экран выводится из состояния сессии.
/// Вход / выход / истечение сессии меняют `SessionService`, и корень переключается автоматически.
@MainActor
@Observable
final class AppRouter {
    /// `true`, когда splash показан не меньше `minimumSplashDuration` и сессия восстановлена.
    private(set) var isSplashFinished = false

    private let sessionService: SessionServiceProtocol
    private let localizationService: LocalizationServiceProtocol
    private let realtimeService: RealtimeServiceProtocol
    private let sessionWork: SessionWorkStarting
    private let minimumSplashDuration: Duration
    /// `true`, пока приложение в фоне: соединение с WebSocket закрыто и откроется при возврате.
    private var isInBackground = false
    #if DEBUG
    /// Состояние debug-входа; пока оно не `nil`, корень — `.debugLogin`.
    private(set) var debugLoginState: DebugLoginState?
    /// Запуск по debug-сценарию; `nil` — обычный старт.
    private var debugLoginLaunch: DebugLoginLaunch?
    #endif

    /// - Parameters:
    ///   - sessionService: сервис сессии, по которому выбирается корневой экран.
    ///   - localizationService: сервис языка интерфейса; его состояние восстанавливается вместе с сессией.
    ///   - realtimeService: соединение с WebSocket — закрывается на время фона и открывается при возврате.
    ///   - sessionWork: начало работы с сервером после восстановления сессии (список переписок, отправка очереди,
    ///     `/global/start`).
    ///   - minimumSplashDuration: минимальное время показа splash — чтобы он не мелькал на один кадр,
    ///     когда сессия восстанавливается мгновенно.
    init(
        sessionService: SessionServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        realtimeService: RealtimeServiceProtocol,
        sessionWork: SessionWorkStarting,
        minimumSplashDuration: Duration = .milliseconds(600)
    ) {
        self.sessionService = sessionService
        self.localizationService = localizationService
        self.realtimeService = realtimeService
        self.sessionWork = sessionWork
        self.minimumSplashDuration = minimumSplashDuration
    }

    var root: AppRoot {
        #if DEBUG
        guard debugLoginState == nil else { return .debugLogin }
        #endif
        guard isSplashFinished else { return .splash }
        return sessionService.isLoggedIn ? .chats : .auth
    }

    /// Локаль текущего языка интерфейса — для форматирования дат, чисел и системных элементов.
    var locale: Locale {
        localizationService.language.locale
    }

    /// Восстанавливает сохранённые язык и сессию при старте, удерживая splash не меньше `minimumSplashDuration`.
    /// Сразу после восстановления сессии начинает работу с сервером (`SessionWorkStarting`) — splash её не ждёт.
    func restoreSession() async {
        #if DEBUG
        if let debugLoginLaunch {
            await performDebugLogin(debugLoginLaunch)
            return
        }
        #endif
        let splashHold = Task { try? await Task.sleep(for: minimumSplashDuration) }
        await localizationService.restore()
        await sessionService.restore()
        sessionWork.startSessionWork()
        await splashHold.value
        isSplashFinished = true
    }

    /// Уход в фон закрывает соединение с WebSocket; возврат из фона начинает работу заново с `/global/start`.
    /// Прочие переходы (неактивное состояние при шторке, системном алерте) соединение не трогают.
    ///
    /// Пока идёт debug-сценарий (вход или экран ошибки), фаза только запоминается, а соединение не трогается: работа
    /// с сервером ещё не начата, и возврат из фона открыл бы соединение со старой cookie или раньше списка переписок
    /// (2003 разлогинил бы только что вошедшего пользователя). Фаза применяется при завершении сценария.
    /// - Parameter isActive: `true` — приложение стало активным, `false` — ушло в фон.
    func didChangeScenePhase(isActive: Bool) async {
        #if DEBUG
        guard debugLoginState == nil else {
            isInBackground = !isActive
            return
        }
        #endif
        if isActive {
            guard isInBackground else { return }
            isInBackground = false
            realtimeService.start()
        } else {
            guard !isInBackground else { return }
            isInBackground = true
            await realtimeService.stop()
        }
    }
}

#if DEBUG
// MARK: - Debug-вход

extension AppRouter {
    /// Роутер, который при старте выполнит debug-вход вместо восстановления сессии.
    /// - Parameters:
    ///   - sessionService: сервис сессии, по которому выбирается корневой экран.
    ///   - localizationService: сервис языка интерфейса.
    ///   - realtimeService: соединение с WebSocket.
    ///   - sessionWork: начало работы с сервером — при обычном старте и после пропуска debug-входа.
    ///   - debugLoginLaunch: запуск по debug-сценарию; `nil` — обычный старт.
    ///   - minimumSplashDuration: минимальное время показа splash при обычном старте.
    convenience init(
        sessionService: SessionServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        realtimeService: RealtimeServiceProtocol,
        sessionWork: SessionWorkStarting,
        debugLoginLaunch: DebugLoginLaunch?,
        minimumSplashDuration: Duration = .milliseconds(600)
    ) {
        self.init(
            sessionService: sessionService,
            localizationService: localizationService,
            realtimeService: realtimeService,
            sessionWork: sessionWork,
            minimumSplashDuration: minimumSplashDuration
        )
        self.debugLoginLaunch = debugLoginLaunch
        // Состояние ставится сразу, а не в `restoreSession()`: иначе до его вызова мелькнул бы splash.
        debugLoginState = debugLoginLaunch.map { .inProgress(login: try? $0.arguments.get().login) }
    }

    /// Кнопка «Продолжить без debug-входа» на экране ошибки: корень выводится из сессии как обычно.
    /// Если сессия жива (ошибка разбора аргументов при сохранённой сессии) — начинает работу с сервером, как обычный
    /// старт. После неудачного входа сессии нет: работу начнёт экран авторизации при ручном входе.
    func didTapSkipDebugLogin() {
        guard case .failed = debugLoginState else { return }
        finishDebugLogin()
        guard sessionService.isLoggedIn else { return }
        sessionWork.startSessionWork()
    }

    /// Восстанавливает язык и сессию без начала работы с сервером — она начнётся для нового пользователя, —
    /// затем выполняет вход. Ошибку показывает стартовый экран. Если вход закончился, пока приложение в фоне,
    /// соединение, открытое сервисом входа, закрывается — как при уходе в фон; возврат откроет его заново.
    /// - Parameter launch: разобранные аргументы и сервис debug-входа.
    private func performDebugLogin(_ launch: DebugLoginLaunch) async {
        await localizationService.restore()
        await sessionService.restore()
        switch launch.arguments {
        case .failure(let error):
            debugLoginState = .failed(message: DebugLoginStrings.message(for: error))
        case .success(let credentials):
            do {
                try await launch.service.login(credentials)
                finishDebugLogin()
                guard isInBackground else { return }
                await realtimeService.stop()
            } catch {
                debugLoginState = .failed(message: ErrorMessages.message(for: error))
            }
        }
    }

    /// Завершает debug-сценарий: корень выводится из сессии.
    private func finishDebugLogin() {
        debugLoginState = nil
        isSplashFinished = true
    }
}
#endif
