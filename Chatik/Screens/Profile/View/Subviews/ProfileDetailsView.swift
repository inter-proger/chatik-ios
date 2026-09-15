//
//  ProfileDetailsView.swift
//  Chatik
//

import SwiftUI

/// Секция с полями профиля: имя, логин, идентификатор.
struct ProfileDetailsView: View {
    let profile: ProfileDisplayModel

    var body: some View {
        Section {
            LabeledContent(ProfileStrings.name, value: profile.name)
            LabeledContent(ProfileStrings.login, value: profile.login)
            LabeledContent(ProfileStrings.userId, value: profile.userId)
        }
    }
}

#Preview {
    List {
        ProfileDetailsView(profile: ProfileDisplayModel(name: "Иван", login: "ivan", userId: "1", avatarURL: nil, avatarThumbnailURL: nil))
    }
}
