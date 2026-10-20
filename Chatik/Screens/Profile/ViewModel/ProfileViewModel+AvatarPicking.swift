//
//  ProfileViewModel+AvatarPicking.swift
//  Chatik
//

import Foundation

/// Выбор фото для аватара: диалог источников, пикеры галереи и камеры, результат выбора.
extension ProfileViewModel {
    /// Обработчик нажатия на аватар: если аватара нет — предлагает выбрать источник изображения.
    /// С установленным аватаром и во время загрузки нажатие игнорируется.
    func didTapAvatar() {
        guard let profile, profile.avatarURL == nil, !isUploadingAvatar else { return }
        isAvatarSourcesPresented = true
    }

    /// Обработчик выбора источника: открывает соответствующий пикер.
    /// - Parameter source: выбранный пользователем источник.
    func didSelectAvatarSource(_ source: AvatarSource) {
        presentedAvatarSource = source
    }

    /// Обработчик выбранного изображения: закрывает пикер и запускает установку аватара.
    /// Если загрузка уже идёт, выбор игнорируется, а временный файл из галереи удаляется.
    /// - Parameter image: снимок с камеры или файл из галереи.
    func didPickImage(_ image: PickedImage) {
        presentedAvatarSource = nil
        guard !isUploadingAvatar else {
            discard(image)
            return
        }
        Task { await uploadAvatar(image) }
    }

    /// Удаляет временный файл изображения, если он есть — выбранный файл не будет загружен.
    /// - Parameter image: изображение, от загрузки которого отказались.
    private func discard(_ image: PickedImage) {
        guard case .file(let file) = image else { return }
        imageFileStore.remove(file)
    }

    /// Обработчик ситуации, когда выбранный в галерее файл не удалось прочитать как изображение.
    func didFailToPickImage() {
        presentedAvatarSource = nil
        notifications.showError(ProfileStrings.avatarLoadFailed)
    }
}
