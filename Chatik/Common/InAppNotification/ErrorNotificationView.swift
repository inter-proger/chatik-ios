//
//  ErrorNotificationView.swift
//  Chatik
//

import SwiftUI

/// Карточка уведомления-ошибки: иконка и текст целиком, без ограничения числа строк.
struct ErrorNotificationView: View {
    let message: String

    var body: some View {
        TextNotificationView(systemImage: "exclamationmark.circle.fill", tint: .red, message: message)
    }
}

/// Карточка текстового уведомления: иконка вида, текст целиком и, если по нажатию есть подробности, шеврон.
struct TextNotificationView: View {
    let systemImage: String
    let tint: Color
    let message: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorNotificationView(message: "Нет соединения с сервером. Проверьте подключение к интернету")
        ErrorNotificationView(message: "Неверный пароль")
        TextNotificationView(systemImage: "checkmark.circle.fill", tint: .green, message: "Вы покинули группу")
        TextNotificationView(systemImage: "exclamationmark.triangle.fill", tint: .orange, message: "2 участника не было добавлено", showsChevron: true)
    }
    .padding()
}
