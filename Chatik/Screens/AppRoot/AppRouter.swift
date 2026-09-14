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
    private let minimumSplashDuration: Duration

    /// - Parameters:
    ///   - sessionService: сервис сессии, по которому выбирается корневой экран.
    ///   - localizationService: сервис языка интерфейса; его состояние восстанавливается вместе с сессией.
    ///   - minimumSplashDuration: минимальное время показа splash — чтобы он не мелькал на один кадр,
    ///     когда сессия восстанавливается мгновенно.
    init(
        sessionService: SessionServiceProtocol,
        localizationService: LocalizationServiceProtocol,
        minimumSplashDuration: Duration = .milliseconds(600)
    ) {
        self.sessionService = sessionService
        self.localizationService = localizationService
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
    func restoreSession() async {
        let splashHold = Task { try? await Task.sleep(for: minimumSplashDuration) }
        await localizationService.restore()
        await sessionService.restore()
        await splashHold.value
        isSplashFinished = true
    }
}
