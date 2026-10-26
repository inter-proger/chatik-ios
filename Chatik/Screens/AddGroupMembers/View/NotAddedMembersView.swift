//
//  NotAddedMembersView.swift
//  Chatik
//

import SwiftUI

/// Попап не добавленных: пользователи, сгруппированные по причине. Его можно только закрыть.
struct NotAddedMembersView: View {
    let sections: [NotAddedSectionDisplayModel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sections) { section in
                Section(section.reason) {
                    ForEach(section.users) { user in
                        GroupMemberRowView(member: user)
                    }
                }
            }
            .navigationTitle(AddGroupMembersStrings.notAddedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AddGroupMembersStrings.notAddedClose) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
