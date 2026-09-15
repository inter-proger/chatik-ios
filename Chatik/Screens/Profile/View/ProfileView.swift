//
//  ProfileView.swift
//  Chatik
//

import SwiftUI

/// Экран профиля текущего пользователя: аватар, имя, логин и идентификатор.
/// Открывается внутри `NavigationStack` списка чатов. Нажатие на пустой аватар предлагает выбрать фото.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let profile = viewModel.profile {
                ProfileHeaderView(
                    profile: profile,
                    isUploadingAvatar: viewModel.isUploadingAvatar,
                    onAvatarTap: viewModel.didTapAvatar
                )
                ProfileDetailsView(profile: profile)
            }
        }
        .navigationTitle(ProfileStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.loadProfile() }
        .task { await viewModel.loadProfile() }
        .confirmationDialog(ProfileStrings.avatarTitle, isPresented: $viewModel.isAvatarSourcesPresented, titleVisibility: .visible) {
            ForEach(viewModel.avatarSources, id: \.self) { source in
                Button(viewModel.title(for: source)) { viewModel.didSelectAvatarSource(source) }
            }
        }
        .avatarSourcePickers(
            presentedSource: $viewModel.presentedAvatarSource,
            onPick: viewModel.didPickImage,
            onFailure: viewModel.didFailToPickImage
        )
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

#if DEBUG
#Preview("Без аватара") {
    NavigationStack {
        ProfileView(viewModel: PreviewDependencies.profileViewModel())
    }
}

#Preview("Ошибка загрузки") {
    NavigationStack {
        ProfileView(viewModel: PreviewDependencies.profileViewModel(
            profileResult: .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        ))
    }
}
#endif
