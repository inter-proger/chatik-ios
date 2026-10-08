//
//  ConversationsListView.swift
//  Chatik
//

import SwiftUI

/// Список чатов с бесшовной подгрузкой страниц.
struct ConversationsListView: View {
    let conversations: [ChatRowDisplayModel]
    /// Идентификатор открытой переписки — её строка подсвечена как выбранная. `nil` — подсветки нет.
    let selectedId: Int?
    let isLoadingNextPage: Bool
    let onAppear: (ChatRowDisplayModel) -> Void
    let onSelect: (ChatRowDisplayModel) -> Void

    var body: some View {
        List {
            ForEach(conversations) { conversation in
                Button { onSelect(conversation) } label: {
                    ChatRowView(conversation: conversation)
                }
                .listRowBackground(conversation.id == selectedId ? Color(.systemFill) : nil)
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
        selectedId: 2,
        isLoadingNextPage: false,
        onAppear: { _ in },
        onSelect: { _ in }
    )
}
