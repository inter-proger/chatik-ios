//
//  MessageBubbleView.swift
//  Chatik
//

import SwiftUI

/// Сообщение в ленте: исходящие — справа на фоне акцентного цвета, входящие — слева.
struct MessageBubbleView: View {
    let message: MessageDisplayModel

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 48)
            }
            bubble
            if !message.isOutgoing {
                Spacer(minLength: 48)
            }
        }
    }

    /// Пузырь сообщения: имя отправителя, текст, время и пометка о редактировании.
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let senderName = message.senderName {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .redacted(reason: message.isSenderPlaceholder ? .placeholder : [])
            }
            Text(message.text)
                .italic(message.isUnsupported)
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
        .background(message.isOutgoing ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Время отправки и пометка «изменено» в правом нижнем углу пузыря.
    private var footer: some View {
        HStack(spacing: 4) {
            if let editedLabel = message.editedLabel {
                Text(editedLabel)
            }
            Text(message.time)
        }
        .font(.caption2)
        .opacity(0.7)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: MessageDisplayModel(id: 1, text: "Привет!", isUnsupported: false, isOutgoing: true, senderName: nil, isSenderPlaceholder: false, time: "12:01", editedLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: 2, text: "Привет, как дела?", isUnsupported: false, isOutgoing: false, senderName: "Мария", isSenderPlaceholder: false, time: "12:02", editedLabel: "изменено"))
        MessageBubbleView(message: MessageDisplayModel(id: 3, text: "Сообщение не поддерживается", isUnsupported: true, isOutgoing: false, senderName: "Загрузка…", isSenderPlaceholder: true, time: "12:03", editedLabel: nil))
    }
    .padding()
}
