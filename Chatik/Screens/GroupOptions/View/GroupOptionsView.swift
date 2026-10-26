//
//  GroupOptionsView.swift
//  Chatik
//

import SwiftUI

/// Опции группы: шапка с аватаром, названием и описанием, участники, добавление участников и выход.
struct GroupOptionsView: View {
    @State private var viewModel: GroupOptionsViewModel

    init(viewModel: GroupOptionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                GroupOptionsHeaderView(
                    avatar: viewModel.conversation.avatar,
                    title: viewModel.title,
                    description: viewModel.conversation.description
                )
                .listRowBackground(Color.clear)
            }
            Section {
                membersRow
                if viewModel.canAddMembers {
                    Button(GroupOptionsStrings.addMembers, systemImage: "person.badge.plus", action: viewModel.didTapAddMembers)
                }
            }
            Section {
                leaveRow
            }
        }
        .disabled(viewModel.isLeaving)
        .navigationTitle(GroupOptionsStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        // Пока идёт выход, уйти с экрана нельзя: результат не должен прийти на закрытый экран.
        .navigationBarBackButtonHidden(viewModel.isLeaving)
        .onAppear(perform: viewModel.didAppear)
        .onDisappear(perform: viewModel.didDisappear)
        .alert(GroupOptionsStrings.leaveConfirmTitle, isPresented: $viewModel.isLeaveConfirmationPresented) {
            Button(GroupOptionsStrings.leaveCancel, role: .cancel) {}
            Button(GroupOptionsStrings.leaveConfirmButton, role: .destructive, action: viewModel.didConfirmLeave)
        } message: {
            Text(viewModel.leaveMessage)
        }
    }

    /// «Участники» с числом справа; пока состав неизвестен — индикатор.
    private var membersRow: some View {
        Button(action: viewModel.didTapMembers) {
            HStack {
                Label(GroupOptionsStrings.members, systemImage: "person.2")
                    .foregroundStyle(.primary)
                Spacer()
                if let count = viewModel.membersCount {
                    Text(count, format: .number)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        // Строка ведёт на экран, а не выполняет действие: обычный цвет текста, как у строки навигации; иконка — того же
        // цвета, что текст.
        .tint(.primary)
    }

    /// «Покинуть группу» — красным; во время выхода индикатор в строке.
    private var leaveRow: some View {
        Button(role: .destructive, action: viewModel.didTapLeave) {
            HStack {
                Label(GroupOptionsStrings.leave, systemImage: "rectangle.portrait.and.arrow.right")
                    // Иконка — того же цвета, что текст: `role: .destructive` в `List` красит только текст. Цвет задан
                    // явно, поэтому неактивную строку гасим сами.
                    .foregroundStyle(viewModel.isLeaveEnabled || viewModel.isLeaving ? Color.red : Color.secondary)
                Spacer()
                if viewModel.isLeaving {
                    ProgressView()
                }
            }
        }
        .disabled(!viewModel.isLeaveEnabled)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GroupOptionsView(viewModel: PreviewDependencies.groupOptionsViewModel())
    }
}
#endif
