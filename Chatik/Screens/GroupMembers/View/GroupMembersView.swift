//
//  GroupMembersView.swift
//  Chatik
//

import SwiftUI

/// Участники группы: секции «Создатель» и «Участники». Создатель долгим нажатием на участника открывает меню
/// с «Передать права создателя».
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
            Button(GroupMembersStrings.transferCancel, role: .cancel) {}
            Button(GroupMembersStrings.transferConfirm, role: .destructive) { viewModel.didConfirmTransfer(to: member) }
        } message: { member in
            Text(GroupMembersStrings.transferMessage(name: member.name))
        }
    }

    /// Строка участника; меню по долгому нажатию — только если права можно передать.
    /// - Parameter member: участник.
    @ViewBuilder
    private func row(_ member: GroupMemberDisplayModel) -> some View {
        let rowView = GroupMemberRowView(member: member, trailingText: member.isCurrentUser ? GroupMembersStrings.you : nil)
        if viewModel.canTransferOwnership(to: member) {
            rowView.contextMenu {
                Button(GroupMembersStrings.transferOwnership, systemImage: "crown") {
                    viewModel.didSelectTransferOwnership(to: member)
                }
            }
        } else {
            rowView
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
