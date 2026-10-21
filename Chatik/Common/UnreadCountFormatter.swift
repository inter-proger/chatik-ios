//
//  UnreadCountFormatter.swift
//  Chatik
//

import Foundation

/// Формат счётчиков непрочитанных — один для строки списка, заголовка «Чаты» и кнопки «вниз».
enum UnreadCountFormatter {
    /// Наибольшее число, которое показывается точно; больше — «99+».
    static let maxExactCount = 99

    /// Текст счётчика.
    /// - Parameter count: непрочитанные сообщения.
    /// - Returns: `nil` при 0 (счётчик не показывается), точное число до `maxExactCount`, выше — «99+».
    static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        guard count > maxExactCount else { return String(count) }
        return "\(maxExactCount)+"
    }

    /// Подпись VoiceOver: всегда точное число в нужной форме множественного числа.
    /// - Parameter count: непрочитанные сообщения.
    /// - Returns: `nil` при 0.
    @MainActor
    static func accessibilityLabel(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return CommonStrings.unreadCount(count)
    }
}
