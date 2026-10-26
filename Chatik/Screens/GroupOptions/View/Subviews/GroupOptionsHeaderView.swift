//
//  GroupOptionsHeaderView.swift
//  Chatik
//

import SwiftUI

/// Шапка опций группы: аватар, название и описание.
struct GroupOptionsHeaderView: View {
    let avatar: RemoteFile?
    let title: String
    let description: String?

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(url: avatar?.url, thumbnailURL: avatar?.smallURL, placeholder: .group)
                .frame(width: avatarSize, height: avatarSize)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    GroupOptionsHeaderView(avatar: nil, title: "Команда", description: "Рабочие вопросы")
}
