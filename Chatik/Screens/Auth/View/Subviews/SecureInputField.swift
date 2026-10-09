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
///
/// Фокус наружу отдаётся одним флагом `isFocused`: внутренних полей два, а снаружи важно лишь, редактируется ли пароль.
struct SecureInputField: View {
    let placeholder: String
    @Binding var text: String
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    /// `true`, пока в фокусе любое из внутренних полей. Запись `true` ставит фокус на видимое поле, `false` снимает его.
    @Binding var isFocused: Bool

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
        .onChange(of: focusedField != nil) { _, hasFocus in
            isFocused = hasFocus
        }
        .onChange(of: isFocused) { _, isFocused in
            applyFocus(isFocused)
        }
    }

    /// Ставит фокус на видимое поле или снимает его по запросу снаружи. Если состояние уже совпадает, ничего не делает,
    /// чтобы не перебить фокус, выставленный самим пользователем.
    /// - Parameter isFocused: `true` — поставить фокус, `false` — снять.
    private func applyFocus(_ isFocused: Bool) {
        guard isFocused != (focusedField != nil) else { return }
        focusedField = isFocused ? (isVisible ? .plain : .secure) : nil
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
