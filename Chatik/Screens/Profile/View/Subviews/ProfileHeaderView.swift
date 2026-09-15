//
//  ProfileHeaderView.swift
//  Chatik
//

import SwiftUI

/// Шапка профиля: крупный аватар (кнопка) и имя пользователя.
/// Во время загрузки аватара поверх него показывается прелоадер, кнопка неактивна.
struct ProfileHeaderView: View {
    let profile: ProfileDisplayModel
    let isUploadingAvatar: Bool
    let onAvatarTap: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 12) {
                avatarButton
                Text(profile.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var avatarButton: some View {
        Button(action: onAvatarTap) {
            AvatarView(url: profile.avatarURL, thumbnailURL: profile.avatarThumbnailURL)
                .frame(width: 120, height: 120)
                .overlay {
                    if isUploadingAvatar {
                        Circle().fill(.black.opacity(0.3))
                        ProgressView().tint(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingAvatar)
        .accessibilityLabel(ProfileStrings.avatarTitle)
    }
}

#Preview {
    List {
        ProfileHeaderView(
            profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil),
            isUploadingAvatar: false,
            onAvatarTap: {}
        )
        ProfileHeaderView(
            profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil),
            isUploadingAvatar: true,
            onAvatarTap: {}
        )
    }
}
