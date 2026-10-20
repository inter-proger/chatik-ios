//
//  InAppNotificationStrings.swift
//  Chatik
//

import Foundation

/// Локализованные строки уведомлений в приложении (таблица `InAppNotification.strings`).
@MainActor
enum InAppNotificationStrings {
    private static let table = "InAppNotification"

    static var dismissAction: String { localized("in_app_notification.dismiss") }

    /// Возвращает локализованную строку по ключу из таблицы `InAppNotification`.
    /// - Parameter key: ключ в `InAppNotification.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
