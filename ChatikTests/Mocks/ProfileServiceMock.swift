//
//  ProfileServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса профиля: возвращает заданный результат и считает вызовы.
final class ProfileServiceMock: ProfileServiceProtocol {
    var stubbedProfile: Result<User, Error> = .failure(NetworkError.missingResponse)
    private(set) var fetchProfileCallCount = 0
    private(set) var setAvatarFileIds: [Int] = []
    /// Вызывается внутри `fetchProfile` и `setAvatar` и ожидается до возврата результата — пока ViewModel
    /// гарантированно в состоянии загрузки. `@MainActor`, чтобы из хука можно было читать состояние ViewModel и вызывать её методы.
    var onRequest: (@MainActor () async -> Void)?

    func fetchProfile() async throws -> User {
        fetchProfileCallCount += 1
        await onRequest?()
        return try stubbedProfile.get()
    }

    func setAvatar(fileId: Int) async throws -> User {
        setAvatarFileIds.append(fileId)
        await onRequest?()
        return try stubbedProfile.get()
    }

    func removeAvatar() async throws -> User {
        try stubbedProfile.get()
    }
}
