//
//  SecureInputField.swift
//  Chatik
//

import SwiftUI

/// Поле ввода пароля с переключателем видимости («глаз»).
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    let isVisible: Bool
    let onToggleVisibility: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            inputField
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? AuthStrings.passwordHide : AuthStrings.passwordShow)
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if isVisible {
            TextField(placeholder, text: $text)
        } else {
            SecureField(placeholder, text: $text)
        }
    }
}
