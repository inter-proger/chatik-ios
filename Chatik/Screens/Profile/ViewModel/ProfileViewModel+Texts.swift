//
//  ProfileViewModel+Texts.swift
//  Chatik
//

import Foundation

/// Тексты экрана профиля, зависящие от состояния.
extension ProfileViewModel {
    /// Название варианта в диалоге выбора источника аватара.
    /// - Parameter source: источник изображения.
    func title(for source: AvatarSource) -> String {
        switch source {
        case .gallery: return ProfileStrings.avatarChooseFromGallery
        case .camera: return ProfileStrings.avatarTakePhoto
        }
    }
}
