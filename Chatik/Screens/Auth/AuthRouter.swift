//
//  AuthRouter.swift
//  Chatik
//

import SwiftUI

/// Роутер экрана авторизации. Переход к чатам происходит через смену состояния сессии (`AppRouter`).
@MainActor
@Observable
final class AuthRouter {
    var path = NavigationPath()
}
