//
//  ProfileViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана профиля текущего пользователя. Показывает пользователя из сессии сразу,
/// а при открытии и pull-to-refresh обновляет его с сервера.
@MainActor
@Observable
final class ProfileViewModel {
    /// `true`, пока выполняется запрос профиля.
    private(set) var isLoading = false
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    private let profileService: ProfileServiceProtocol
    private let sessionService: SessionServiceProtocol

    init(profileService: ProfileServiceProtocol, sessionService: SessionServiceProtocol) {
        self.profileService = profileService
        self.sessionService = sessionService
    }

    /// Профиль для отображения — из текущей сессии. `nil` — сессии нет.
    var profile: ProfileDisplayModel? {
        sessionService.currentUser.map(ProfileDisplayModel.init)
    }

    /// Запрашивает актуальный профиль с сервера и обновляет сессию. Повторный вызов во время запроса игнорируется.
    /// При ошибке показывает сообщение, оставляя на экране данные из сессии.
    func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await profileService.fetchProfile()
            await sessionService.update(user: user)
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }
}
