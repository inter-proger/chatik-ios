//
//  ProfileHeaderView.swift
//  Chatik
//

import SwiftUI

/// Шапка профиля: крупный аватар (кнопка) и имя пользователя.
/// Во время загрузки аватара поверх него показывается прогресс отправки, кнопка неактивна.
struct ProfileHeaderView: View {
    let profile: ProfileDisplayModel
    /// Прогресс загрузки аватара от 0 до 1; `nil` — загрузки нет.
    let uploadProgress: Double?
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
                    if let uploadProgress {
                        AvatarUploadProgressView(progress: uploadProgress)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(uploadProgress != nil)
        .accessibilityLabel(ProfileStrings.avatarTitle)
    }
}

#Preview {
    List {
        ProfileHeaderView(
            profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil),
            uploadProgress: nil,
            onAvatarTap: {}
        )
        ProfileHeaderView(
            profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil),
            uploadProgress: 0.6,
            onAvatarTap: {}
        )
    }
}
