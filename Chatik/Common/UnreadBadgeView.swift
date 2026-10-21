//
//  UnreadBadgeView.swift
//  Chatik
//

import SwiftUI

/// Капсула счётчика непрочитанных акцентного цвета. Текст уже отформатирован (`UnreadCountFormatter`).
struct UnreadBadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.accentColor, in: Capsule())
    }
}

#Preview {
    HStack {
        UnreadBadgeView(text: "1")
        UnreadBadgeView(text: "42")
        UnreadBadgeView(text: "99+")
    }
}
