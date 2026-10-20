//
//  InAppNotificationTiming.swift
//  Chatik
//

import UIKit

/// Время показа уведомлений: все константы — здесь.
enum InAppNotificationTiming {
    /// Время показа короткого уведомления.
    static let baseDuration: Duration = .seconds(2)
    /// Длина текста ошибки, которая укладывается в базовое время.
    static let shortTextLength = 40
    /// Добавка за каждый символ сверх `shortTextLength`.
    static let perExtraCharacter: Duration = .milliseconds(50)
    /// Верхняя граница времени показа без VoiceOver.
    static let maxDuration: Duration = .seconds(6)
    /// Время показа с VoiceOver: объявление должны успеть дослушать.
    static let voiceOverDuration: Duration = .seconds(10)

    /// Время показа с учётом текущего состояния VoiceOver.
    /// - Parameter content: содержимое уведомления.
    @MainActor
    static func duration(for content: InAppNotification.Content) -> Duration {
        duration(for: content, isVoiceOverRunning: UIAccessibility.isVoiceOverRunning)
    }

    /// Время показа уведомления.
    /// - Parameters:
    ///   - content: содержимое уведомления.
    ///   - isVoiceOverRunning: включён ли VoiceOver.
    static func duration(for content: InAppNotification.Content, isVoiceOverRunning: Bool) -> Duration {
        guard !isVoiceOverRunning else { return voiceOverDuration }
        switch content {
        case .error(let message):
            return textDuration(length: message.count)
        }
    }

    /// Базовое время плюс добавка за символы сверх короткого текста, не больше верхней границы.
    /// - Parameter length: длина текста в символах.
    private static func textDuration(length: Int) -> Duration {
        let extraCharacters = max(0, length - shortTextLength)
        return min(baseDuration + perExtraCharacter * extraCharacters, maxDuration)
    }
}
