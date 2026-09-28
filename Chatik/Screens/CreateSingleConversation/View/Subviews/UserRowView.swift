//
//  UserRowView.swift
//  Chatik
//

import SwiftUI

/// Строка списка выбора собеседника: аватар, имя, логин и отметка выбора.
struct UserRowView: View {
    let user: UserRowDisplayModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarURL)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .foregroundStyle(.primary)
                Text(user.login)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    List {
        UserRowView(user: UserRowDisplayModel(id: 1, name: "Иван Петров", login: "@ivan", avatarURL: nil), isSelected: true)
        UserRowView(user: UserRowDisplayModel(id: 2, name: "Мария", login: "@maria", avatarURL: nil), isSelected: false)
    }
}
