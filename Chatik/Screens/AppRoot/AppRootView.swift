//
//  AppRootView.swift
//  Chatik
//

import SwiftUI

/// Корень приложения: splash на время восстановления сессии (в Debug — стартовый экран debug-входа), затем экран
/// авторизации или список чатов.
struct AppRootView: View {
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter router: роутер приложения; по умолчанию создаётся над сессией из `DIContainer`.
    init(router: AppRouter? = nil) {
        _router = State(initialValue: router ?? Self.makeRouter())
    }

    var body: some View {
        Group {
            switch router.root {
            case .splash:
                SplashView()
            #if DEBUG
            case .debugLogin:
                DebugLoginView(
                    state: router.debugLoginState ?? .inProgress(login: nil),
                    onSkip: router.didTapSkipDebugLogin
                )
            #endif
            case .auth:
                AuthRootView()
            case .chats:
                ChatListRootView()
            }
        }
        .animation(.default, value: router.root)
        .environment(\.locale, router.locale)
        .inAppNotifications(DIContainer.shared.notificationService)
        .task { await router.restoreSession() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            Task { await router.didChangeScenePhase(isActive: phase == .active) }
        }
    }

    /// Роутер над сервисами из `DIContainer`; в Debug-сборке — с debug-входом, если он передан аргументами запуска.
    private static func makeRouter() -> AppRouter {
        let container = DIContainer.shared
        #if DEBUG
        return AppRouter(
            sessionService: container.sessionService,
            localizationService: container.localizationService,
            realtimeService: container.realtimeService,
            sessionWork: container.sessionWorkLauncher,
            debugLoginLaunch: container.debugLoginLaunch
        )
        #else
        return AppRouter(
            sessionService: container.sessionService,
            localizationService: container.localizationService,
            realtimeService: container.realtimeService,
            sessionWork: container.sessionWorkLauncher
        )
        #endif
    }
}

#Preview {
    AppRootView()
}
