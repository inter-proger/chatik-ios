//
//  ProfileHeaderView.swift
//  Chatik
//

import SwiftUI

/// Шапка профиля: крупный аватар и имя пользователя.
struct ProfileHeaderView: View {
    let profile: ProfileDisplayModel

    var body: some View {
        Section {
            VStack(spacing: 12) {
                AvatarView(url: profile.avatarURL, thumbnailURL: profile.avatarThumbnailURL)
                    .frame(width: 120, height: 120)
                Text(profile.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    List {
        ProfileHeaderView(profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil))
    }
}
