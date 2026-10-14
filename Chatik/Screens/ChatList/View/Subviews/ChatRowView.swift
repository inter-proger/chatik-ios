//
//  ChatRowView.swift
//  Chatik
//

import SwiftUI

/// Строка списка чатов: аватар, название, время и превью последнего сообщения.
struct ChatRowView: View {
    let conversation: ChatRowDisplayModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: conversation.avatarURL)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .redacted(reason: conversation.isTitlePlaceholder ? .placeholder : [])
                    Spacer(minLength: 8)
                    Text(conversation.time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        ChatRowView(conversation: ChatRowDisplayModel(id: 1, title: "Иван Петров", avatarURL: nil, preview: "Привет!", time: "12:30"))
        ChatRowView(conversation: ChatRowDisplayModel(id: 2, title: "Команда", avatarURL: nil, time: "11 окт."))
        ChatRowView(conversation: ChatRowDisplayModel(id: 3, title: "Загрузка…", isTitlePlaceholder: true, avatarURL: nil))
    }
}
