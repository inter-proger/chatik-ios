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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AuthLanguageMenu(selected: viewModel.language, onSelect: viewModel.selectLanguage)
            }
        }
        .onAppear(perform: viewModel.handleAppear)
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent()) {
            Button(CommonStrings.ok, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
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

    /// Кнопка действия. Во время запроса текст скрывается (сохраняя размер кнопки), поверх — прелоадер.
    private var primaryButton: some View {
        Button(action: viewModel.didTapPrimaryButton) {
            Text(viewModel.primaryButtonTitle)
                .font(.headline)
                .opacity(viewModel.isLoading ? 0 : 1)
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
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
        sessionService: DIContainer.shared.sessionService,
        localizationService: DIContainer.shared.localizationService,
        signupValidator: DIContainer.shared.signupValidator,
        loginValidator: DIContainer.shared.loginValidator,
        router: AuthRouter()
    ))
}

#Preview("Вход") {
    AuthView(viewModel: AuthViewModel(
        mode: .login,
        authService: DIContainer.shared.authService,
        sessionService: DIContainer.shared.sessionService,
        localizationService: DIContainer.shared.localizationService,
        signupValidator: DIContainer.shared.signupValidator,
        loginValidator: DIContainer.shared.loginValidator,
        router: AuthRouter()
    ))
}
