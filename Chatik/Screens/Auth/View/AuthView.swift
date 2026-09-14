//
//  AuthView.swift
//  Chatik
//

import SwiftUI

/// Экран регистрации / входа.
struct AuthView: View {
    @State private var viewModel: AuthViewModel

    init(viewModel: AuthViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                AuthFormView(viewModel: viewModel)
                agreementIfNeeded
                primaryButton
                AuthModeSwitchView(
                    text: viewModel.switchModeText,
                    actionURL: AuthViewModel.switchModeURL,
                    onTap: viewModel.switchMode
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.default, value: viewModel.isSignup)
    }

    private var header: some View {
        Text(viewModel.title)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var agreementIfNeeded: some View {
        if viewModel.isSignup {
            Text(viewModel.agreementText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var primaryButton: some View {
        Button(action: viewModel.didTapPrimaryButton) {
            Text(viewModel.primaryButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isPrimaryButtonEnabled)
    }
}

#Preview("Регистрация") {
    AuthView(viewModel: AuthViewModel(
        mode: .signup,
        authService: DIContainer.shared.authService,
        signupValidator: DIContainer.shared.signupValidator,
        loginValidator: DIContainer.shared.loginValidator,
        router: AuthRouter()
    ))
}

#Preview("Вход") {
    AuthView(viewModel: AuthViewModel(
        mode: .login,
        authService: DIContainer.shared.authService,
        signupValidator: DIContainer.shared.signupValidator,
        loginValidator: DIContainer.shared.loginValidator,
        router: AuthRouter()
    ))
}
