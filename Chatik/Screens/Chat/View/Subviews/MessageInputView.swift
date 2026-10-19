//
//  MessageInputView.swift
//  Chatik
//

import SwiftUI

/// Панель ввода сообщения: многострочное поле и кнопка отправки. Отправка не блокирует ввод: сообщение сразу
/// уходит в ленту, а поле очищается для следующего. Сохранение правки блокирует: пока идёт запрос, поле только
/// для чтения (текст правки должен совпадать с отправленным), а на месте значка кнопки — индикатор того же размера.
struct MessageInputView: View {
    @Binding var text: String
    /// Фокус поля ввода — им управляет экран (например, убирает клавиатуру по тапу по ленте).
    var isFocused: FocusState<Bool>.Binding
    /// Подсказка под полем (например, о превышении длины); `nil` — подсказки нет.
    let hint: String?
    let isSendEnabled: Bool
    /// Идёт запрос правки: поле недоступно, на кнопке индикатор.
    var isSubmitting = false
    /// Значок кнопки: отправка или сохранение правки.
    var sendIcon = "arrow.up.circle.fill"
    /// Подпись кнопки для VoiceOver.
    var sendLabel = ChatStrings.send
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                textField
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Поле ввода, растущее до пяти строк.
    private var textField: some View {
        TextField(ChatStrings.inputPlaceholder, text: $text, axis: .vertical)
            .lineLimit(1...5)
            .focused(isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .disabled(isSubmitting)
    }

    /// Кнопка отправки или сохранения правки. Во время запроса значок скрыт прозрачностью, а не убран: размер
    /// кнопки не меняется.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: sendIcon)
                .font(.system(size: 32))
                .opacity(isSubmitting ? 0 : 1)
                .overlay {
                    if isSubmitting {
                        ProgressView()
                    }
                }
        }
        .disabled(!isSendEnabled)
        .accessibilityLabel(sendLabel)
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    VStack {
        Spacer()
        MessageInputView(text: .constant("Привет!"), isFocused: $isFocused, hint: nil, isSendEnabled: true, onSend: {})
        MessageInputView(text: .constant(""), isFocused: $isFocused, hint: "Сообщение не должно быть длиннее 4096 символов", isSendEnabled: false, onSend: {})
        MessageInputView(text: .constant("Исправленный текст"), isFocused: $isFocused, hint: nil, isSendEnabled: false, isSubmitting: true, sendIcon: "checkmark.circle.fill", onSend: {})
    }
    .background(.bar)
}
