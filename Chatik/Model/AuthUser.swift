//
//  AuthUser.swift
//  Chatik
//

import Foundation

/// Авторизованный пользователь — ответ `/auth/signup` и `/auth/login`.
struct AuthUser: Codable, Equatable {
    let userId: Int
    let name: String
}
