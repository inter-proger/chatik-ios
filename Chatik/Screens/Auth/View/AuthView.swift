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
        // Тап по пустому месту или тексту скрывает клавиатуру. Жесты кнопок, ссылок и полей вложены глубже
        // и срабатывают вместо этого. Фон за ScrollView ловит тапы и ниже контента, куда сам ScrollView их не отдаёт.
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: UIApplication.shared.dismissKeyboard)
        }
        .onTapGesture(perform: UIApplication.shared.dismissKeyboard)
        .animation(.default, value: viewModel.isSignup)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AuthLanguageMenu(selected: viewModel.language, onSelect: viewModel.selectLanguage)
            }
        }
        .onAppear(perform: viewModel.showExpirationIfNeeded)
        // По активности сервиса уведомлений, а не по `scenePhase`: порядок `onChange` этого экрана и корня, который
        // включает сервис, не гарантирован.
        .onChange(of: viewModel.canShowNotifications) { _, canShow in
            guard canShow else { return }
            viewModel.showExpirationIfNeeded()
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

    /// Скрывает клавиатуру сразу по нажатию, ещё до начала запроса, и запускает регистрацию / вход.
    private func didTapPrimaryButton() {
        UIApplication.shared.dismissKeyboard()
        viewModel.didTapPrimaryButton()
    }

    /// Кнопка действия. Во время запроса текст скрывается (сохраняя размер кнопки), поверх — прелоадер.
    private var primaryButton: some View {
        Button(action: didTapPrimaryButton) {
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

#if DEBUG
#Preview("Регистрация") {
    NavigationStack {
        AuthView(viewModel: PreviewDependencies.authViewModel(mode: .signup))
    }
}

#Preview("Вход") {
    NavigationStack {
        AuthView(viewModel: PreviewDependencies.authViewModel(mode: .login))
    }
}

#Preview("Ошибка сервера") {
    NavigationStack {
        AuthView(viewModel: PreviewDependencies.authViewModel(
            mode: .login,
            authResult: .failure(NetworkError.api(code: NetworkError.Code.wrongCredentials))
        ))
    }
}
#endif
