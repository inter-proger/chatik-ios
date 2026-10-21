//
//  MessageNotificationView.swift
//  Chatik
//

import SwiftUI

/// Карточка уведомления о новом сообщении: аватар отправителя, заголовок переписки и текст в одну строку.
struct MessageNotificationView: View {
    let model: MessageNotificationDisplayModel

    /// Размер аватара.
    private static let avatarSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: model.avatarURL)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(model.text)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageNotificationView(model: MessageNotificationDisplayModel(
            conversationId: 1,
            messageId: 1,
            title: "Анна Петрова",
            avatarURL: nil,
            text: AttributedString("Привет! Как дела? Давно не виделись, давай встретимся на выходных")
        ))
        MessageNotificationView(model: MessageNotificationDisplayModel(
            conversationId: 2,
            messageId: 2,
            title: "Команда",
            avatarURL: nil,
            text: AttributedString("Иван: созвон в 15:00")
        ))
    }
    .padding()
}
