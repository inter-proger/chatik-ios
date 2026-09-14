//
//  AppRootView.swift
//  Chatik
//

import SwiftUI

/// Корень приложения: splash на время восстановления сессии, затем экран авторизации или список чатов.
struct AppRootView: View {
    @State private var router: AppRouter

    /// - Parameter router: роутер приложения; по умолчанию создаётся над сессией из `DIContainer`.
    init(router: AppRouter? = nil) {
        _router = State(initialValue: router ?? AppRouter(sessionService: DIContainer.shared.sessionService))
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
        .task { await router.restoreSession() }
    }
}

#Preview {
    AppRootView()
}
