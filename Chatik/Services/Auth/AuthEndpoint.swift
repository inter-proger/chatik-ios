//
//  AuthEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/auth/*`. Сессия ведётся через cookie `PHPSESSID`,
/// которую `URLSession` сохраняет и подставляет автоматически.
enum AuthEndpoint: Endpoint {
    /// POST /auth/signup — регистрация. Ответ: `AuthUser`.
    case signup(login: String, password: String, name: String)
    /// POST /auth/login — авторизация. Ответ: `AuthUser`.
    case login(login: String, password: String)
    /// POST /auth/logout — завершение сессии. Ответ: `EmptyResponse`.
    case logout

    var path: String {
        switch self {
        case .signup: return "/auth/signup"
        case .login: return "/auth/login"
        case .logout: return "/auth/logout"
        }
    }

    var method: HTTPMethod { .post }

    var parameters: [String: String] {
        switch self {
        case let .signup(login, password, name):
            return ["login": login, "password": password, "name": name]
        case let .login(login, password):
            return ["login": login, "password": password]
        case .logout:
            return [:]
        }
    }

    var headers: [String: String]? { nil }
}
