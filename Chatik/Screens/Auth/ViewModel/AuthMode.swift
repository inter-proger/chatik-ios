//
//  AuthMode.swift
//  Chatik
//

import Foundation

/// Режим экрана авторизации.
enum AuthMode {
    case signup
    case login

    /// Противоположный режим — используется при переключении по ссылке внизу экрана.
    var toggled: AuthMode {
        switch self {
        case .signup: return .login
        case .login: return .signup
        }
    }
}
