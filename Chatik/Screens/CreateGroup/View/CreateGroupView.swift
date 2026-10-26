//
//  CreateGroupView.swift
//  Chatik
//

import SwiftUI

/// Экран создания группы: аватар, название, описание и кнопка «Создать». Показывается модально поверх списка чатов.
struct CreateGroupView: View {
    @State private var viewModel: CreateGroupViewModel

    init(viewModel: CreateGroupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                CreateGroupAvatarView(
                    preview: viewModel.avatarPreview,
                    progress: viewModel.avatarUploader.progress,
                    onTap: viewModel.didTapAvatar
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField(CreateGroupStrings.namePlaceholder, text: $viewModel.name)
                    .textInputAutocapitalization(.sentences)
            } footer: {
                hint(for: viewModel.nameError)
            }
            Section {
                TextField(CreateGroupStrings.descriptionPlaceholder, text: $viewModel.groupDescription, axis: .vertical)
                    .lineLimit(1...5)
            } footer: {
                hint(for: viewModel.descriptionError)
            }
        }
        .disabled(viewModel.isCreating)
        .navigationTitle(CreateGroupStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .interactiveDismissDisabled(viewModel.isInteractiveDismissDisabled)
        .onDisappear(perform: viewModel.didDisappear)
        .confirmationDialog(CreateGroupStrings.avatarTitle, isPresented: $viewModel.isAvatarSourcesPresented, titleVisibility: .visible) {
            ForEach(viewModel.avatarSources, id: \.self) { source in
                Button(viewModel.title(for: source)) { viewModel.didSelectAvatarSource(source) }
            }
            if viewModel.hasAvatar {
                Button(CreateGroupStrings.avatarRemove, role: .destructive, action: viewModel.didTapRemoveAvatar)
            }
        }
        .avatarSourcePickers(
            presentedSource: $viewModel.presentedAvatarSource,
            onPick: viewModel.didPickImage,
            onFailure: viewModel.didFailToPickImage
        )
    }

    /// Подсказка под полем, если текст длиннее лимита.
    /// - Parameter error: ошибка поля.
    @ViewBuilder
    private func hint(for error: GroupFieldError?) -> some View {
        if let text = viewModel.hint(for: error) {
            Text(text)
                .foregroundStyle(.red)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(CreateGroupStrings.cancel, action: viewModel.didTapCancel)
                .disabled(viewModel.isCreating)
        }
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.isCreating {
                ProgressView()
            } else {
                Button(CreateGroupStrings.create, action: viewModel.didTapCreate)
                    .disabled(!viewModel.isCreateButtonEnabled)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateGroupView(viewModel: PreviewDependencies.createGroupViewModel())
    }
}
#endif
