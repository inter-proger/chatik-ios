//
//  GroupMembersView.swift
//  Chatik
//

import SwiftUI

/// Участники группы: секции «Создатель» и «Участники». Долгое нажатие на участника открывает меню: «Личный диалог»,
/// а у создателя ещё «Передать права создателя» и «Исключить из группы».
struct GroupMembersView: View {
    @State private var viewModel: GroupMembersViewModel

    init(viewModel: GroupMembersViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let content = viewModel.content {
                if let owner = content.owner {
                    Section(GroupMembersStrings.ownerSection) {
                        row(owner)
                    }
                }
                if !content.members.isEmpty {
                    Section(GroupMembersStrings.membersSection) {
                        ForEach(content.members) { member in
                            row(member)
                        }
                    }
                }
            }
        }
        .overlay { stateOverlay }
        .refreshable { await viewModel.reload() }
        .navigationTitle(GroupMembersStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: viewModel.didAppear)
        .onDisappear(perform: viewModel.didDisappear)
        .task(id: viewModel.content) { viewModel.loadMissingUsers() }
        // Участник передаётся в кнопку алерта: привязка обнуляет `pendingTransfer` при закрытии, и к нажатию «ОК»
        // его в ViewModel уже может не быть.
        .alert(
            GroupMembersStrings.transferTitle,
            isPresented: $viewModel.isTransferConfirmationPresented,
            presenting: viewModel.pendingTransfer
        ) { member in
            Button(GroupMembersStrings.cancel, role: .cancel) {}
            Button(GroupMembersStrings.transferConfirm, role: .destructive) { viewModel.didConfirmTransfer(to: member) }
        } message: { member in
            Text(GroupMembersStrings.transferMessage(name: member.name))
        }
        .alert(
            GroupMembersStrings.removeTitle,
            isPresented: $viewModel.isRemoveConfirmationPresented,
            presenting: viewModel.pendingRemoval
        ) { member in
            Button(GroupMembersStrings.cancel, role: .cancel) {}
            Button(GroupMembersStrings.removeConfirm, role: .destructive) { viewModel.didConfirmRemoval(of: member) }
        } message: { member in
            Text(GroupMembersStrings.removeMessage(name: member.name))
        }
    }

    /// Строка участника; меню по долгому нажатию — из действий для участника (пустое меню не показывается).
    /// Пока создаётся личный диалог с участником, в его строке индикатор.
    /// - Parameter member: участник.
    private func row(_ member: GroupMemberDisplayModel) -> some View {
        GroupMemberRowView(
            member: member,
            trailingText: member.isCurrentUser ? GroupMembersStrings.you : nil,
            isLoading: viewModel.openingChatMemberId == member.id
        )
        .contextMenu {
            ForEach(viewModel.actions(for: member), id: \.self) { action in
                menuButton(action, for: member)
            }
        }
    }

    /// Пункт меню участника.
    /// - Parameters:
    ///   - action: действие.
    ///   - member: участник.
    @ViewBuilder
    private func menuButton(_ action: GroupMemberAction, for member: GroupMemberDisplayModel) -> some View {
        switch action {
        case .directChat:
            Button(GroupMembersStrings.directChat, systemImage: "bubble.left") { viewModel.didSelect(action, for: member) }
        case .transferOwnership:
            Button(GroupMembersStrings.transferOwnership, systemImage: "crown") { viewModel.didSelect(action, for: member) }
        case .remove:
            Button(GroupMembersStrings.remove, systemImage: "person.badge.minus", role: .destructive) {
                viewModel.didSelect(action, for: member)
            }
        }
    }

    /// Загрузка или ошибка, пока состав неизвестен.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.content == nil {
            if viewModel.isFailed {
                ContentUnavailableView {
                    Label(GroupMembersStrings.loadFailed, systemImage: "person.2.slash")
                } actions: {
                    Button(GroupMembersStrings.retry, action: viewModel.didTapRetry)
                }
            } else {
                ProgressView()
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GroupMembersView(viewModel: PreviewDependencies.groupMembersViewModel())
    }
}
#endif
