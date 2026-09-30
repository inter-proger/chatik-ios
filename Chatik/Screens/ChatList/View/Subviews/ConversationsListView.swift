//
//  ConversationsListView.swift
//  Chatik
//

import SwiftUI

/// Список чатов с бесшовной подгрузкой страниц.
struct ConversationsListView: View {
    let conversations: [ChatRowDisplayModel]
    let isLoadingNextPage: Bool
    let onAppear: (ChatRowDisplayModel) -> Void

    var body: some View {
        List {
            ForEach(conversations) { conversation in
                ChatRowView(conversation: conversation)
                    .onAppear { onAppear(conversation) }
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

#Preview {
    ConversationsListView(
        conversations: [
            ChatRowDisplayModel(id: 1, title: "Иван Петров", avatarURL: nil),
            ChatRowDisplayModel(id: 2, title: "Команда", avatarURL: nil),
        ],
        isLoadingNextPage: false,
        onAppear: { _ in }
    )
}
