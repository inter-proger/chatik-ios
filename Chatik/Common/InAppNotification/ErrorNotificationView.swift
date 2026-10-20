//
//  ErrorNotificationView.swift
//  Chatik
//

import SwiftUI

/// Карточка уведомления-ошибки: иконка и текст целиком, без ограничения числа строк.
struct ErrorNotificationView: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    }
    .padding()
}
