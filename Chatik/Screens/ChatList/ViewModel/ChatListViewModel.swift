//
//  ChatListViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана списка чатов. Пока содержит переход в профиль, создание личного диалога и выход из аккаунта.
@MainActor
@Observable
final class ChatListViewModel {
    /// `true`, пока выполняется запрос выхода.
    private(set) var isLoggingOut = false
    /// Текст ошибки для всплывающего сообщения. `nil` — сообщение скрыто.
    var errorMessage: String?

    private let authService: AuthServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let router: ChatListRouter

    init(
        authService: AuthServiceProtocol,
        sessionService: SessionServiceProtocol,
        router: ChatListRouter
    ) {
        self.authService = authService
        self.sessionService = sessionService
        self.router = router
    }

    /// URL аватара текущего пользователя для кнопки профиля: уменьшенная копия, если она есть.
    /// `nil` — аватар не установлен, кнопка показывает изображение по умолчанию.
    var avatarURL: URL? {
        guard let avatar = sessionService.currentUser?.avatar else { return nil }
        return avatar.smallURL ?? avatar.url
    }

    /// Обработчик кнопки-аватара: открывает экран профиля.
    func didTapProfile() {
        router.showProfile()
    }

    /// Обработчик пункта «Личный диалог» меню создания: открывает экран создания личного диалога.
    func didTapCreateSingleConversation() {
        router.showCreateSingleConversation()
    }

    /// Обработчик кнопки «Выйти»: запускает выход, если он ещё не выполняется.
    func didTapLogout() {
        guard !isLoggingOut else { return }
        Task { await logout() }
    }

    /// Завершает сессию на сервере и локально; приложение переключится на экран авторизации.
    /// Если сервер ответил «не авторизован», сессии уже нет — завершаем локально без сообщения об ошибке.
    /// При прочих ошибках показывает сообщение и остаётся на экране.
    func logout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        do {
            try await authService.logout()
            await sessionService.end()
        } catch NetworkError.api(let code) where code == NetworkError.Code.unauthorized {
            await sessionService.end()
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }
}
