//
//  ChatRowView.swift
//  Chatik
//

import SwiftUI

/// Строка списка чатов: аватар, название, время, превью — черновик или последнее сообщение — и счётчик
/// непрочитанных.
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
                HStack(alignment: .center, spacing: 8) {
                    previewText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let unreadCountText = conversation.unreadCountText {
                        UnreadBadgeView(text: unreadCountText)
                            .accessibilityLabel(conversation.unreadAccessibilityLabel ?? unreadCountText)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// Превью: у черновика и неотправленного сообщения части без цвета наследуют `.secondary`, обрезка работает
    /// по всей строке.
    private var previewText: Text {
        switch conversation.preview {
        case let .message(text): Text(text)
        case let .labeled(text): Text(text)
        }
    }
}

#Preview {
    List {
        ChatRowView(conversation: ChatRowDisplayModel(id: 1, title: "Иван Петров", avatarURL: nil, preview: .message("Привет!"), time: "12:30", unreadCountText: "3"))
        ChatRowView(conversation: ChatRowDisplayModel(id: 4, title: "Мария Иванова", avatarURL: nil, preview: .labeled(ChatRowDisplayModel.localPreview(.draft("Завтра в 15:00 подойдёт?"))), time: "12:10"))
        ChatRowView(conversation: ChatRowDisplayModel(id: 5, title: "Пётр Сидоров", avatarURL: nil, preview: .labeled(ChatRowDisplayModel.localPreview(.failed("Скинь, пожалуйста, адрес"))), time: "11:45"))
        ChatRowView(conversation: ChatRowDisplayModel(id: 2, title: "Команда", avatarURL: nil, preview: .message("Новый чат"), time: "11 окт."))
        ChatRowView(conversation: ChatRowDisplayModel(id: 3, title: "Загрузка…", isTitlePlaceholder: true, avatarURL: nil))
    }
}

