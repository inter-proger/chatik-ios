//
//  ChatListView.swift
//  Chatik
//

import SwiftUI

/// Экран списка чатов. Пока — заглушка с кнопкой выхода.
struct ChatListView: View {
    @State private var viewModel: ChatListViewModel

    init(viewModel: ChatListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Text(ChatListStrings.empty)
            .foregroundStyle(.secondary)
            .navigationTitle(ChatListStrings.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    logoutButton
                }
            }
            .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
                Button(CommonStrings.ok, role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    /// Кнопка выхода; во время запроса заменяется прелоадером.
    @ViewBuilder
    private var logoutButton: some View {
        if viewModel.isLoggingOut {
            ProgressView()
        } else {
            Button(ChatListStrings.logout, action: viewModel.didTapLogout)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ChatListView(viewModel: PreviewDependencies.chatListViewModel())
    }
}
#endif
