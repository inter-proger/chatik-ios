//
//  ChatListView.swift
//  Chatik
//

import SwiftUI

/// Экран списка чатов. Пока — заглушка с кнопками профиля, создания диалога и выхода.
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
                ToolbarItem(placement: .topBarLeading) {
                    profileButton
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    logoutButton
                    createMenu
                }
            }
            .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
                Button(CommonStrings.ok, role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    /// Кнопка открытия профиля в виде аватарки текущего пользователя.
    private var profileButton: some View {
        Button(action: viewModel.didTapProfile) {
            AvatarView(url: viewModel.avatarURL)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(ChatListStrings.profile)
    }

    /// Кнопка «+» со списком того, что можно создать.
    private var createMenu: some View {
        Menu {
            Button(ChatListStrings.createSingle, systemImage: "person", action: viewModel.didTapCreateSingleConversation)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(ChatListStrings.create)
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
