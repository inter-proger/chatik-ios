//
//  InAppNotification.swift
//  Chatik
//

import Foundation
import SwiftUI

/// Уведомление в приложении: что показать, сколько держать на экране и что делать по нажатию.
struct InAppNotification: Identifiable {
    let id = UUID()
    /// Момент создания — порядок карточек при замене: новая рисуется поверх уходящей.
    let createdAt = ProcessInfo.processInfo.systemUptime
    let content: Content
    /// Время показа.
    let duration: Duration
    /// Тактильный отклик при появлении; `nil` — без отклика.
    let feedback: SensoryFeedback?
    /// Действие по нажатию; `nil` — нажатие ничего не делает (ошибки).
    let onTap: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - content: что показать.
    ///   - duration: время показа; `nil` — по виду и тексту (`InAppNotificationTiming.duration(for:)`).
    ///   - feedback: отклик при появлении; `.none` — отклик вида (`Content.defaultFeedback`), `.some(nil)` — без
    ///     отклика.
    ///   - onTap: действие по нажатию.
    @MainActor
    init(
        content: Content,
        duration: Duration? = nil,
        feedback: SensoryFeedback?? = .none,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        self.content = content
        self.duration = duration ?? InAppNotificationTiming.duration(for: content)
        self.feedback = feedback ?? content.defaultFeedback
        self.onTap = onTap
    }

    /// Содержимое уведомления: по нему выбирается внешний вид и узнаётся повтор.
    enum Content: Equatable {
        /// Ошибка: текст уже готов к показу (`ErrorMessages.message(for:)`).
        case error(message: String)

        /// Тактильный отклик вида по умолчанию.
        var defaultFeedback: SensoryFeedback? {
            switch self {
            case .error: .error
            }
        }
    }
}
