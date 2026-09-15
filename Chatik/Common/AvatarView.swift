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
/// по умолчанию, силуэт человека. Оно же показывается при `url == nil` и при ошибке загрузки.
/// Размер задаётся снаружи через `.frame`.
struct AvatarView: View {
    let url: URL?
    /// Уменьшенная копия для показа на время загрузки `url`. `nil` — сразу изображение по умолчанию.
    var thumbnailURL: URL? = nil

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
            .placeholder { placeholder }
            .resizable()
            .scaledToFill()
    }

    /// Изображение по умолчанию для пустого аватара.
    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(spacing: 16) {
        AvatarView(url: nil)
            .frame(width: 96, height: 96)
        AvatarView(url: nil)
            .frame(width: 32, height: 32)
    }
}
