//
//  AppRouter.swift
//  Chatik
//

import Foundation

/// Корневой экран приложения.
enum AppRoot: Equatable {
    /// Splash-экран: сессия читается из хранилища.
    case splash
    case auth
    case chats
}

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
        let splashHold = Task { try? await Task.sleep(for: minimumSplashDuration) }
        await localizationService.restore()
        await sessionService.restore()
        sessionWork.startSessionWork()
        await splashHold.value
        isSplashFinished = true
    }

    /// Уход в фон закрывает соединение с WebSocket; возврат из фона начинает работу заново с `/global/start`.
    /// Прочие переходы (неактивное состояние при шторке, системном алерте) соединение не трогают.
    /// - Parameter isActive: `true` — приложение стало активным, `false` — ушло в фон.
    func didChangeScenePhase(isActive: Bool) async {
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
