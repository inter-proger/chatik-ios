//
//  AddMemberRowView.swift
//  Chatik
//

import SwiftUI

/// Строка экрана добавления: аватар, имя, логин и галочка выбора; участник группы — с подписью «В группе».
struct AddMemberRowView: View {
    let row: AddMemberRowDisplayModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: row.user.avatarURL)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.user.name)
                    .foregroundStyle(.primary)
                Text(row.user.login)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .opacity(row.isDisabled && !row.isMember ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    /// Подпись «В группе» или галочка выбора.
    @ViewBuilder
    private var trailing: some View {
        if row.isMember {
            Text(AddGroupMembersStrings.inGroup)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(row.isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
        }
    }
}
