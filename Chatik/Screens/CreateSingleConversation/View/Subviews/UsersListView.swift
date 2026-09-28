//
//  UsersListView.swift
//  Chatik
//

import SwiftUI

/// Список пользователей для выбора собеседника с бесшовной подгрузкой страниц.
struct UsersListView: View {
    let users: [UserRowDisplayModel]
    let selectedUserId: Int?
    let isLoadingNextPage: Bool
    let onSelect: (UserRowDisplayModel) -> Void
    let onAppear: (UserRowDisplayModel) -> Void

    var body: some View {
        List {
            ForEach(users) { user in
                Button { onSelect(user) } label: {
                    UserRowView(user: user, isSelected: user.id == selectedUserId)
                }
                .buttonStyle(.plain)
                .onAppear { onAppear(user) }
            }
            if isLoadingNextPage {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}
