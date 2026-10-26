//
//  CreateGroupAvatarView.swift
//  Chatik
//

import SwiftUI

/// Аватар создаваемой группы: превью выбранного изображения или значок камеры, прогресс загрузки поверх.
struct CreateGroupAvatarView: View {
    /// Превью выбранного изображения; `nil` — аватар не выбран.
    let preview: UIImage?
    /// Прогресс загрузки; `nil` — загрузка не идёт.
    let progress: Double?
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 96

    var body: some View {
        Button(action: onTap) {
            image
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if let progress {
                        AvatarUploadProgressView(progress: progress)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CreateGroupStrings.avatarAccessibilityLabel)
    }

    /// Превью или круг со значком камеры.
    @ViewBuilder
    private var image: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(Color(.secondarySystemFill))
                .overlay {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        CreateGroupAvatarView(preview: nil, progress: nil, onTap: {})
        CreateGroupAvatarView(preview: nil, progress: 0.4, onTap: {})
    }
}
