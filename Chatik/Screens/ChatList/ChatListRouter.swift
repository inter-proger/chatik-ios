//
//  ChatListRouter.swift
//  Chatik
//

import SwiftUI

/// Роутер экрана списка чатов. Возврат к авторизации происходит через смену состояния сессии (`AppRouter`).
@MainActor
@Observable
final class ChatListRouter {
    var path = NavigationPath()
}
