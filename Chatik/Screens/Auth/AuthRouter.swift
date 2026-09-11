//
//  AuthRouter.swift
//  Chatik
//

import SwiftUI

/// Роутер экрана авторизации. Переходы после успешного входа будут добавлены вместе с логикой.
@MainActor
@Observable
final class AuthRouter {
    var path = NavigationPath()
}
