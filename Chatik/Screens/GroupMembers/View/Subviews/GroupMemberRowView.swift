//
//  GroupMemberRowView.swift
//  Chatik
//

import SwiftUI

/// Строка участника группы: аватар, имя и подпись «Вы» у текущего пользователя.
struct GroupMemberRowView: View {
    let member: GroupMemberDisplayModel
    /// Подпись справа; `nil` — без подписи.
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: member.avatarURL)
                .frame(width: 36, height: 36)
            Text(member.name)
                .lineLimit(1)
                .redacted(reason: member.isPlaceholder ? .placeholder : [])
            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        GroupMemberRowView(member: GroupMemberDisplayModel(id: 1, name: "Иван Петров", isPlaceholder: false, avatarURL: nil, isCurrentUser: true), trailingText: "Вы")
        GroupMemberRowView(member: GroupMemberDisplayModel(id: 2, name: "Загрузка…", isPlaceholder: true, avatarURL: nil, isCurrentUser: false))
    }
}
