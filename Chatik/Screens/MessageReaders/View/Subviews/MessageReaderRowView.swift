//
//  MessageReaderRowView.swift
//  Chatik
//

import SwiftUI

/// Строка списка прочитавших: аватар и имя; пока участник не загружен — заглушка вместо имени.
struct MessageReaderRowView: View {
    let reader: MessageReaderDisplayModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: reader.avatarURL)
                .frame(width: 36, height: 36)
            Text(reader.name)
                .lineLimit(1)
                .redacted(reason: reader.isPlaceholder ? .placeholder : [])
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        MessageReaderRowView(reader: MessageReaderDisplayModel(id: 1, name: "Иван Петров", isPlaceholder: false, avatarURL: nil))
        MessageReaderRowView(reader: MessageReaderDisplayModel(id: 2, name: "Загрузка…", isPlaceholder: true, avatarURL: nil))
    }
}
