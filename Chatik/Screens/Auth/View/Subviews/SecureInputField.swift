//
//  SecureInputField.swift
//  Chatik
//

import SwiftUI

/// Поле ввода пароля с переключателем видимости («глаз»).
///
/// Оба поля (`SecureField` и `TextField`) существуют одновременно и переключаются прозрачностью —
/// если заменять их через `if`, SwiftUI создаёт новое view и клавиатура сбрасывается.
/// При переключении фокус переносится на видимое поле, поэтому клавиатура остаётся открытой.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    /// Вызывается при получении (`true`) и потере (`false`) фокуса любым из внутренних полей.
    var onFocusChange: (Bool) -> Void = { _ in }

    @FocusState private var focusedField: Field?

    private enum Field {
        case secure
        case plain
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                SecureField(placeholder, text: $text)
                    .focused($focusedField, equals: .secure)
                    .hiddenWhen(isVisible)

                TextField(placeholder, text: $text)
                    .focused($focusedField, equals: .plain)
                    .hiddenWhen(!isVisible)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? AuthStrings.passwordHide : AuthStrings.passwordShow)
        }
        .onChange(of: isVisible) { _, isVisible in
            moveFocusIfNeeded(toPlain: isVisible)
        }
        .onChange(of: focusedField != nil) { _, isFocused in
            onFocusChange(isFocused)
        }
    }

    /// Переносит фокус на поле, ставшее видимым, если пользователь в этот момент редактировал пароль.
    /// - Parameter toPlain: `true` — фокус на открытое поле, `false` — на секьюрное.
    private func moveFocusIfNeeded(toPlain: Bool) {
        guard focusedField != nil else { return }
        focusedField = toPlain ? .plain : .secure
    }
}

private extension View {
    /// Скрывает поле, не убирая его из иерархии: невидимо, не реагирует на тапы и недоступно для VoiceOver.
    /// - Parameter hidden: нужно ли скрыть view.
    func hiddenWhen(_ hidden: Bool) -> some View {
        self
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
