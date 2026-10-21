//
//  UnreadMessagesHeaderView.swift
//  Chatik
//

import SwiftUI

/// Заголовок «Непрочитанные сообщения» в ленте над первым непрочитанным сообщением: полоса во всю ширину, чтобы
/// не путаться с капсулой даты. На плавающую дату не влияет — кадр трекеру не сообщает.
struct UnreadMessagesHeaderView: View {
    var body: some View {
        Text(ChatStrings.unreadHeader)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.6))
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    UnreadMessagesHeaderView()
        .padding()
}
