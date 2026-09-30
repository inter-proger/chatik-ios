//
//  ChatRowView.swift
//  Chatik
//

import SwiftUI

/// Строка списка чатов: аватар и название переписки.
struct ChatRowView: View {
    let conversation: ChatRowDisplayModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: conversation.avatarURL)
                .frame(width: 48, height: 48)
            Text(conversation.title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        ChatRowView(conversation: ChatRowDisplayModel(id: 1, title: "Иван Петров", avatarURL: nil))
        ChatRowView(conversation: ChatRowDisplayModel(id: 2, title: "Команда", avatarURL: nil))
    }
}
