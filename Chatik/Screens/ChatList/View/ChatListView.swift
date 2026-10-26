//
//  ChatListView.swift
//  Chatik
//

import SwiftUI

/// Экран списка чатов: список переписок с бесшовной подгрузкой страниц, кнопки профиля
/// и создания диалога. Заголовок всегда компактный — по центру панели навигации; пока список синхронизируется
/// с сервером, вместо названия — «Обновление…» с индикатором, а список из кэша остаётся интерактивным.
struct ChatListView: View {
    @State private var viewModel: ChatListViewModel

    init(viewModel: ChatListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ConversationsListView(
            conversations: viewModel.conversations,
            selectedId: viewModel.selectedConversationId,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            onAppear: viewModel.prefetchNextPageIfNeeded,
            onSelect: viewModel.didSelectConversation
        )
        .overlay { stateOverlay }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.observeDayChanges() }
        .task { await viewModel.observeConversations() }
        .navigationTitle(ChatListStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
            ToolbarItem(placement: .topBarLeading) {
                profileButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                createMenu
            }
        }
    }

    /// Прелоадер первой загрузки или сообщение о пустом списке поверх списка. Пока идёт синхронизация поверх
    /// кэша, ни того ни другого нет — об обновлении говорит заголовок.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isLoadingFirstPage {
            ProgressView()
        } else if viewModel.isEmpty {
            ContentUnavailableView(ChatListStrings.empty, systemImage: "bubble.left.and.bubble.right")
        }
    }

    /// Заголовок: название экрана и общий счётчик непрочитанных или, пока идёт синхронизация, индикатор
    /// и «Обновление…».
    @ViewBuilder
    private var titleView: some View {
        if viewModel.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                Text(ChatListStrings.updating)
            }
            .font(.headline)
        } else {
            HStack(spacing: 6) {
                Text(ChatListStrings.title)
                    .font(.headline)
                if let totalUnreadText = viewModel.totalUnreadText {
                    UnreadBadgeView(text: totalUnreadText)
                        .accessibilityLabel(viewModel.totalUnreadAccessibilityLabel ?? totalUnreadText)
                }
            }
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
            Button(ChatListStrings.createGroup, systemImage: "person.2", action: viewModel.didTapCreateGroup)
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
