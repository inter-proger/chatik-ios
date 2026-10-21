//
//  InAppNotificationServiceMock.swift
//  ChatikTests
//

import Foundation
import Observation
@testable import Chatik

/// Мок сервиса уведомлений: запоминает показанные уведомления; в неактивном состоянии отбрасывает их, как настоящий.
@MainActor
@Observable
final class InAppNotificationServiceMock: InAppNotificationServiceProtocol {
    private(set) var current: InAppNotification?
    var isActive = true
    var presentingSceneId: UUID?
    /// Активные сцены: задаются через `setActive`.
    private(set) var activeSceneIds: Set<UUID> = []
    /// Все принятые к показу уведомления по порядку.
    private(set) var shown: [InAppNotification] = []

    /// Тексты показанных ошибок по порядку.
    var shownErrors: [String] {
        shown.compactMap { notification in
            guard case let .error(message) = notification.content else { return nil }
            return message
        }
    }

    /// Показанные уведомления о сообщениях по порядку.
    var shownMessages: [MessageNotificationDisplayModel] {
        shown.compactMap { notification in
            guard case let .message(model) = notification.content else { return nil }
            return model
        }
    }

    @discardableResult
    func show(_ notification: InAppNotification) -> Bool {
        guard isActive else { return false }
        shown.append(notification)
        current = notification
        return true
    }

    func dismiss(id: InAppNotification.ID) {
        guard current?.id == id else { return }
        current = nil
    }

    func pauseTimer(id: InAppNotification.ID) {}

    func resumeTimer(id: InAppNotification.ID) {}

    func isSceneActive(_ sceneId: UUID) -> Bool {
        activeSceneIds.contains(sceneId)
    }

    func setActive(_ isActive: Bool, sceneId: UUID) {
        self.isActive = isActive
        presentingSceneId = isActive ? sceneId : nil
        if isActive {
            activeSceneIds.insert(sceneId)
        } else {
            activeSceneIds.remove(sceneId)
        }
    }
}
