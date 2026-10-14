//
//  AppRootView.swift
//  Chatik
//

import SwiftUI

/// Корень приложения: splash на время восстановления сессии, затем экран авторизации или список чатов.
struct AppRootView: View {
    @State private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter router: роутер приложения; по умолчанию создаётся над сессией из `DIContainer`.
    init(router: AppRouter? = nil) {
        _router = State(initialValue: router ?? AppRouter(
            sessionService: DIContainer.shared.sessionService,
            localizationService: DIContainer.shared.localizationService,
            realtimeService: DIContainer.shared.realtimeService,
            conversationList: DIContainer.shared.conversationListService,
            messageSendQueue: DIContainer.shared.messageSendQueue
        ))
    }

    var body: some View {
        Group {
            switch router.root {
            case .splash:
                SplashView()
            case .auth:
                AuthRootView()
            case .chats:
                ChatListRootView()
            }
        }
        .animation(.default, value: router.root)
        .environment(\.locale, router.locale)
        .task { await router.restoreSession() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            Task { await router.didChangeScenePhase(isActive: phase == .active) }
        }
    }
}

#Preview {
    AppRootView()
}
