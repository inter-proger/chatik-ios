//
//  MessageAction+Display.swift
//  Chatik
//

import Foundation

/// Вид действия с сообщением — один для меню сообщения и для действий VoiceOver.
extension MessageAction {
    /// Название пункта.
    @MainActor
    var title: String {
        switch self {
        case .edit: ChatStrings.messageActionEdit
        case .retrySending: ChatStrings.messageActionRetrySending
        case .deleteUnsent: ChatStrings.messageActionDeleteUnsent
        }
    }

    /// Значок пункта (SF Symbol).
    var systemImage: String {
        switch self {
        case .edit: "pencil"
        case .retrySending: "arrow.clockwise"
        case .deleteUnsent: "trash"
        }
    }

    /// Действие удаляет данные: пункт выделяется красным, для VoiceOver — роль `.destructive`.
    var isDestructive: Bool {
        switch self {
        case .edit, .retrySending: false
        case .deleteUnsent: true
        }
    }
}
