//
//  ProfileService.swift
//  Chatik
//

import Foundation

protocol ProfileServiceProtocol {
    /// Возвращает профиль текущего пользователя.
    func fetchProfile() async throws -> User
    /// Устанавливает аватар из ранее загруженного изображения и возвращает обновлённый профиль.
    func setAvatar(fileId: Int) async throws -> User
    /// Убирает аватар и возвращает обновлённый профиль. Если аватара не было — тоже успех.
    func removeAvatar() async throws -> User
}

final class ProfileService: ProfileServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает профиль через `GET /profile/get`.
    func fetchProfile() async throws -> User {
        try await networkService.request(ProfileEndpoint.get)
    }

    /// Устанавливает аватар через `POST /profile/setAvatar`.
    /// - Parameter fileId: идентификатор изображения, загруженного этим же пользователем через `/files/uploadImage`.
    func setAvatar(fileId: Int) async throws -> User {
        try await networkService.request(ProfileEndpoint.setAvatar(fileId: fileId))
    }

    /// Убирает аватар через `POST /profile/removeAvatar`.
    func removeAvatar() async throws -> User {
        try await networkService.request(ProfileEndpoint.removeAvatar)
    }
}
