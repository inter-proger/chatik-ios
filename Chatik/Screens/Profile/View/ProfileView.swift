//
//  ProfileView.swift
//  Chatik
//

import SwiftUI

/// Экран профиля текущего пользователя: аватар, имя, логин и идентификатор.
/// Открывается внутри `NavigationStack` списка чатов.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if let profile = viewModel.profile {
                ProfileHeaderView(profile: profile)
                ProfileDetailsView(profile: profile)
            }
        }
        .navigationTitle(ProfileStrings.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.loadProfile() }
        .task { await viewModel.loadProfile() }
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

#if DEBUG
#Preview("С аватаром") {
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
