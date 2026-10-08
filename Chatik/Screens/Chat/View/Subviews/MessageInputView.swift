//
//  MessageInputView.swift
//  Chatik
//

import SwiftUI

/// Панель ввода сообщения: многострочное поле и кнопка отправки. Отправка не блокирует ввод: сообщение сразу
/// уходит в ленту, а поле очищается для следующего.
struct MessageInputView: View {
    @Binding var text: String
    /// Фокус поля ввода — им управляет экран (например, убирает клавиатуру по тапу по ленте).
    var isFocused: FocusState<Bool>.Binding
    /// Подсказка под полем (например, о превышении длины); `nil` — подсказки нет.
    let hint: String?
    let isSendEnabled: Bool
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
        .background(.bar)
    }

    /// Поле ввода, растущее до пяти строк.
    private var textField: some View {
        TextField(ChatStrings.inputPlaceholder, text: $text, axis: .vertical)
            .lineLimit(1...5)
            .focused(isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Кнопка отправки.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
        }
        .disabled(!isSendEnabled)
        .accessibilityLabel(ChatStrings.send)
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    VStack {
        Spacer()
        MessageInputView(text: .constant("Привет!"), isFocused: $isFocused, hint: nil, isSendEnabled: true, onSend: {})
        MessageInputView(text: .constant(""), isFocused: $isFocused, hint: "Сообщение не должно быть длиннее 4096 символов", isSendEnabled: false, onSend: {})
    }
}
