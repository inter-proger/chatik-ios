//
//  CreateSingleConversationView.swift
//  Chatik
//

import SwiftUI

/// Экран создания личного диалога: поиск и выбор собеседника, кнопка «Создать».
/// Показывается модально поверх списка чатов; закрытие — через роутер, и по отмене, и после создания переписки.
struct CreateSingleConversationView: View {
    @State private var viewModel: CreateSingleConversationViewModel

    init(viewModel: CreateSingleConversationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        UsersListView(
            users: viewModel.users,
            selectedUserId: viewModel.selectedUserId,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            onSelect: viewModel.didSelect,
            onAppear: viewModel.prefetchNextPageIfNeeded
        )
        .overlay { stateOverlay }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: CreateSingleConversationStrings.searchPrompt
        )
        .refreshable { await viewModel.loadFirstPage() }
        // Срабатывает при открытии и при каждом вводе; предыдущий запуск отменяется — так работает пауза поиска.
        .task(id: viewModel.searchText) { await viewModel.searchTextDidChange() }
        .navigationTitle(CreateSingleConversationStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .interactiveDismissDisabled(viewModel.isCreating)
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// Прелоадер первой страницы или сообщение о пустом списке поверх списка.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isLoadingFirstPage && viewModel.users.isEmpty {
            ProgressView()
        } else if viewModel.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.isEmpty
                    ? CreateSingleConversationStrings.emptyTitle
                    : CreateSingleConversationStrings.emptySearchTitle,
                systemImage: "person.2.slash"
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(CreateSingleConversationStrings.cancel, action: viewModel.didTapCancel)
                .disabled(viewModel.isCreating)
        }
        ToolbarItem(placement: .confirmationAction) {
            createButton
        }
    }

    /// Кнопка «Создать»; во время запроса заменяется прелоадером.
    @ViewBuilder
    private var createButton: some View {
        if viewModel.isCreating {
            ProgressView()
        } else {
            Button(CreateSingleConversationStrings.create, action: viewModel.didTapCreate)
                .disabled(!viewModel.isCreateButtonEnabled)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateSingleConversationView(viewModel: PreviewDependencies.createSingleConversationViewModel())
    }
}
#endif
