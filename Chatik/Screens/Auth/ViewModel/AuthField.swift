//
//  AuthField.swift
//  Chatik
//

import Foundation

/// Поле формы авторизации — используется для управления фокусом и состоянием подсказок.
enum AuthField: Hashable {
    case name
    case login
    case password
}

/// Готовое к отображению состояние поля: текст под полем и признак ошибки (красная рамка).
struct AuthFieldState: Equatable {
    /// Подсказка о требованиях (при фокусе) или текст ошибки (после потери фокуса).
    var message: String?
    /// `true` — поле подсвечивается как невалидное.
    var isError = false

    static let empty = AuthFieldState()
}
