//
//  MessageDateHeaderView.swift
//  Chatik
//

import SwiftUI

/// Заголовок дня в ленте — капсула с датой по центру. Только сама капсула: внешние отступы добавляет лента,
/// чтобы трекер плавающей даты знал кадр именно капсулы. Тот же View рисует плавающую плашку
/// (`FloatingDateHeaderView`), поэтому плашка неотличима от заголовка.
struct MessageDateHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            // Ротор «Заголовки» VoiceOver переходит между днями.
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageDateHeaderView(title: "Сегодня, 15 октября")
        MessageDateHeaderView(title: "Среда, 30 декабря 2026 г.")
    }
}
