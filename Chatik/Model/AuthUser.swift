//
//  AuthUser.swift
//  Chatik
//

import Foundation

/// Авторизованный пользователь — ответ `/auth/signup` и `/auth/login`.
nonisolated struct AuthUser: Decodable, Equatable {
    let userId: Int
    let name: String
}
