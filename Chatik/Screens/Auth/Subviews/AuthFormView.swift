//
//  AuthFormView.swift
//  Chatik
//

import SwiftUI

/// Блок полей ввода: имя (только для регистрации), логин, пароль.
struct AuthFormView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isSignup {
                TextField(AuthStrings.fieldName, text: $viewModel.name)
                    .textContentType(.name)
                    .authFieldStyle()
            }

            TextField(AuthStrings.fieldLogin, text: $viewModel.login)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .authFieldStyle()

            SecureInputField(
                placeholder: AuthStrings.fieldPassword,
                text: $viewModel.password,
                isVisible: viewModel.isPasswordVisible,
                onToggleVisibility: viewModel.togglePasswordVisibility
            )
            .textContentType(viewModel.isSignup ? .newPassword : .password)
            .authFieldStyle()
        }
    }
}

private extension View {
    /// Единый стиль полей ввода экрана авторизации.
    func authFieldStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
