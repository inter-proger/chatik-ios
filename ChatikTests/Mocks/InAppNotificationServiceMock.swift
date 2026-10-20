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
    /// Все принятые к показу уведомления по порядку.
    private(set) var shown: [InAppNotification] = []

    /// Тексты показанных ошибок по порядку.
    var shownErrors: [String] {
        shown.map { notification in
            switch notification.content {
            case .error(let message): message
            }
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

    func setActive(_ isActive: Bool, sceneId: UUID) {
        self.isActive = isActive
        presentingSceneId = isActive ? sceneId : nil
    }
}
