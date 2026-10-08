//
//  ChatListView.swift
//  Chatik
//

import SwiftUI

/// Экран списка чатов: список переписок с бесшовной подгрузкой страниц, кнопки профиля
/// и создания диалога. Заголовок всегда компактный — по центру панели навигации.
struct ChatListView: View {
    @State private var viewModel: ChatListViewModel

    init(viewModel: ChatListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ConversationsListView(
            conversations: viewModel.conversations,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            onAppear: viewModel.prefetchNextPageIfNeeded,
            onSelect: viewModel.didSelectConversation
        )
        .overlay { stateOverlay }
        .refreshable { await viewModel.loadFirstPage() }
        .task { await viewModel.loadFirstPage() }
        .navigationTitle(ChatListStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                profileButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                createMenu
            }
        }
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// Прелоадер первой страницы или сообщение о пустом списке поверх списка.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isLoadingFirstPage && viewModel.conversations.isEmpty {
            ProgressView()
        } else if viewModel.isEmpty {
            ContentUnavailableView(ChatListStrings.empty, systemImage: "bubble.left.and.bubble.right")
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
}

#if DEBUG
#Preview {
    NavigationStack {
        ChatListView(viewModel: PreviewDependencies.chatListViewModel())
    }
}
#endif
