//
//  AuthFormView.swift
//  Chatik
//

import SwiftUI

/// Блок полей ввода: имя (только для регистрации), логин, пароль.
struct AuthFormView: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var focusedField: AuthField?

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isSignup {
                AuthFieldContainer(state: viewModel.nameFieldState) {
                    TextField(AuthStrings.fieldName, text: $viewModel.name)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                }
            }

            AuthFieldContainer(state: viewModel.loginFieldState) {
                TextField(AuthStrings.fieldLogin, text: $viewModel.login)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .login)
            }

            AuthFieldContainer(state: viewModel.passwordFieldState) {
                SecureInputField(
                    placeholder: AuthStrings.fieldPassword,
                    text: $viewModel.password,
                    isVisible: viewModel.isPasswordVisible,
                    onToggleVisibility: viewModel.togglePasswordVisibility,
                    onFocusChange: handlePasswordFocusChange
                )
                .textContentType(viewModel.isSignup ? .newPassword : .password)
            }
        }
        .onChange(of: focusedField) { _, field in
            handleTextFieldFocusChange(field)
        }
    }

    /// Прокидывает фокус полей имени / логина во ViewModel. Уход фокуса с них не сбрасывает
    /// фокус пароля — он приходит отдельным событием и может прийти раньше.
    /// - Parameter field: поле, получившее фокус, или `nil`, если фокус ушёл.
    private func handleTextFieldFocusChange(_ field: AuthField?) {
        if let field {
            viewModel.focusedField = field
        } else if viewModel.focusedField != .password {
            viewModel.focusedField = nil
        }
    }

    /// Прокидывает фокус поля пароля во ViewModel, не затирая фокус, уже перешедший на другое поле.
    /// - Parameter isFocused: `true`, если поле пароля получило фокус.
    private func handlePasswordFocusChange(_ isFocused: Bool) {
        if isFocused {
            viewModel.focusedField = .password
        } else if viewModel.focusedField == .password {
            viewModel.focusedField = nil
        }
    }
}
