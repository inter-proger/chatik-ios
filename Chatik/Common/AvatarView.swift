//
//  AvatarView.swift
//  Chatik
//

import Kingfisher
import SwiftUI

/// Круглый аватар пользователя. Изображение грузится через Kingfisher (кэш в памяти и на диске).
///
/// Загрузка двухступенчатая: пока грузится полноразмерное изображение `url`, на его месте показывается
/// уменьшенная копия `thumbnailURL` (как правило, уже в кэше после списка), а пока нет и её — изображение
/// по умолчанию — силуэт человека или, у группы, двух людей. Оно же показывается при `url == nil` и при ошибке загрузки.
/// Размер задаётся снаружи через `.frame`.
struct AvatarView: View {
    let url: URL?
    /// Уменьшенная копия для показа на время загрузки `url`. `nil` — сразу изображение по умолчанию.
    var thumbnailURL: URL? = nil
    /// Изображение по умолчанию: силуэт человека или группы.
    var placeholder: AvatarPlaceholder = .person

    var body: some View {
        KFImage(url)
            .placeholder { thumbnail }
            .resizable()
            .scaledToFill()
            .clipShape(Circle())
    }

    /// Уменьшенная копия; пока грузится она — изображение по умолчанию.
    private var thumbnail: some View {
        KFImage(thumbnailURL)
            .placeholder { placeholderImage }
            .resizable()
            .scaledToFill()
    }

    /// Изображение по умолчанию для пустого аватара.
    private var placeholderImage: some View {
        Image(systemName: placeholder.systemImage)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}

/// Изображение по умолчанию для пустого аватара.
enum AvatarPlaceholder {
    case person
    case group

    /// SF Symbol изображения.
    var systemImage: String {
        switch self {
        case .person: "person.crop.circle.fill"
        case .group: "person.2.circle.fill"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AvatarView(url: nil)
            .frame(width: 96, height: 96)
        AvatarView(url: nil)
            .frame(width: 32, height: 32)
        AvatarView(url: nil, placeholder: .group)
            .frame(width: 96, height: 96)
    }
}
