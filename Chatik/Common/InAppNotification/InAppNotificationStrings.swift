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
    static var messageUntitled: String { localized("in_app_notification.message.untitled") }
    static var messageUnknownSender: String { localized("in_app_notification.message.unknown_sender") }
    static var messageDeletedSender: String { localized("in_app_notification.message.deleted_sender") }
    static var messageUnsupported: String { localized("in_app_notification.message.unsupported") }

    static var noLongerMemberUntitled: String { localized("in_app_notification.group.no_longer_member_untitled") }

    /// Уведомление: пользователь больше не участник открытой группы.
    /// - Parameter groupName: название группы.
    static func noLongerMember(groupName: String) -> String {
        String(format: localized("in_app_notification.group.no_longer_member"), groupName)
    }

    /// Объявление VoiceOver о новом сообщении.
    /// - Parameters:
    ///   - title: заголовок уведомления.
    ///   - text: текст уведомления.
    static func messageAnnouncement(title: String, text: String) -> String {
        String(format: localized("in_app_notification.message.announcement"), title, text)
    }

    /// Возвращает локализованную строку по ключу из таблицы `InAppNotification`.
    /// - Parameter key: ключ в `InAppNotification.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
