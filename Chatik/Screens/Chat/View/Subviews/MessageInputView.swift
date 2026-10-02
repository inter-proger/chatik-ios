//
//  MessageInputView.swift
//  Chatik
//

import SwiftUI

/// Панель ввода сообщения: многострочное поле и кнопка отправки. Во время отправки поле недоступно,
/// а кнопка показывает прелоадер вместо иконки.
struct MessageInputView: View {
    @Binding var text: String
    /// Подсказка под полем (например, о превышении длины); `nil` — подсказки нет.
    let hint: String?
    let isSending: Bool
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .disabled(isSending)
    }

    /// Кнопка отправки; во время запроса иконка скрывается с сохранением размера, поверх — прелоадер.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .opacity(isSending ? 0 : 1)
                .overlay {
                    if isSending {
                        ProgressView()
                    }
                }
        }
        .disabled(!isSendEnabled)
        .accessibilityLabel(ChatStrings.send)
    }
}

#Preview {
    VStack {
        Spacer()
        MessageInputView(text: .constant("Привет!"), hint: nil, isSending: false, isSendEnabled: true, onSend: {})
        MessageInputView(text: .constant("Привет!"), hint: nil, isSending: true, isSendEnabled: false, onSend: {})
        MessageInputView(text: .constant(""), hint: "Сообщение не должно быть длиннее 4096 символов", isSending: false, isSendEnabled: false, onSend: {})
    }
}
