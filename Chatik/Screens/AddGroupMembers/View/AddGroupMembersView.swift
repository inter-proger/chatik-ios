//
//  AddGroupMembersView.swift
//  Chatik
//

import SwiftUI

/// Добавление участников: поиск, фильтр «Все пользователи» / «Не в группе», множественный выбор с лимитом
/// и кнопка «Добавить». Заголовок — «Добавить участников» или «Добавить: X».
struct AddGroupMembersView: View {
    @State private var viewModel: AddGroupMembersViewModel

    init(viewModel: AddGroupMembersViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await viewModel.loadSnapshot() }
            .sheet(item: $viewModel.presentedNotAdded) { report in
                NotAddedMembersView(sections: viewModel.notAddedSections(for: report))
            }
    }

    /// Список, а пока снимок состава не загружен — индикатор или ошибка.
    @ViewBuilder
    private var content: some View {
        if viewModel.snapshot != nil {
            usersList
        } else if viewModel.isSnapshotFailed {
            ContentUnavailableView {
                Label(AddGroupMembersStrings.loadFailed, systemImage: "person.2.slash")
            } actions: {
                Button(AddGroupMembersStrings.retry) { Task { await viewModel.loadSnapshot() } }
            }
        } else {
            ProgressView()
        }
    }

    private var usersList: some View {
        List {
            Section {
                ForEach(viewModel.rows) { row in
                    Button { viewModel.didToggle(row) } label: { AddMemberRowView(row: row) }
                        .buttonStyle(.plain)
                        .disabled(row.isDisabled)
                        .onAppear { viewModel.prefetchNextPageIfNeeded(currentRow: row) }
                }
                if viewModel.isLoadingNextPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } header: {
                header
            }
        }
        .overlay { stateOverlay }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: AddGroupMembersStrings.searchPrompt
        )
        .refreshable { await viewModel.loadFirstPage() }
        .task(id: viewModel.searchText) { await viewModel.searchTextDidChange() }
    }

    /// Фильтр и подсказка о лимите над списком.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $viewModel.filter) {
                Text(AddGroupMembersStrings.filterAll).tag(AddGroupMembersFilter.all)
                Text(AddGroupMembersStrings.filterNotInGroup).tag(AddGroupMembersFilter.notInGroup)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            if viewModel.isLimitReached {
                Text(AddGroupMembersStrings.limitReached)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    /// Прелоадер первой страницы или пустой список.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isLoadingFirstPage && viewModel.rows.isEmpty {
            ProgressView()
        } else if viewModel.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.isEmpty ? AddGroupMembersStrings.emptyTitle : AddGroupMembersStrings.emptySearchTitle,
                systemImage: "person.2.slash"
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isAdding {
                ProgressView()
            } else {
                Button(AddGroupMembersStrings.add, action: viewModel.didTapAdd)
                    .disabled(!viewModel.isAddButtonEnabled)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AddGroupMembersView(viewModel: PreviewDependencies.addGroupMembersViewModel())
    }
}
#endif
