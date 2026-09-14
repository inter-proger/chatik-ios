//
//  AuthRootView.swift
//  Chatik
//

import SwiftUI

/// Корневой контейнер экрана авторизации: владеет роутером и NavigationStack.
struct AuthRootView: View {
    @State private var router = AuthRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            AuthView(viewModel: AuthViewModel(
                authService: DIContainer.shared.authService,
                sessionService: DIContainer.shared.sessionService,
                signupValidator: DIContainer.shared.signupValidator,
                loginValidator: DIContainer.shared.loginValidator,
                router: router
            ))
        }
    }
}

#Preview {
    AuthRootView()
}
