//
//  MessageMenuPresenterMock.swift
//  ChatikTests
//

import UIKit
@testable import Chatik

/// Мок показа меню: запоминает показы и даёт тесту закрыть меню (`close`).
@MainActor
final class MessageMenuPresenterMock: MessageMenuPresenting {
    /// Показанные меню: сообщение и кадр пузыря.
    private(set) var presented: [(message: MessageDisplayModel, frame: CGRect)] = []
    /// Сколько раз меню закрывали извне (`dismiss`).
    private(set) var dismissCount = 0
    /// `true` — показ отклоняется, как у окна, которое ещё не убрано.
    var isRefusing = false
    private var onClose: ((MessageAction?) -> Void)?

    func present(
        message: MessageDisplayModel,
        frame: CGRect,
        source: MessageMenuSource,
        onClose: @escaping (MessageAction?) -> Void
    ) -> Bool {
        guard !isRefusing else { return false }
        presented.append((message, frame))
        self.onClose = onClose
        return true
    }

    func dismiss() {
        dismissCount += 1
        close(with: nil)
    }

    /// Закрывает показанное меню.
    /// - Parameter action: выбранное действие; `nil` — без выбора.
    func close(with action: MessageAction?) {
        onClose?(action)
        onClose = nil
    }
}

/// Мок пузыря-источника меню с задаваемым кадром.
@MainActor
final class MessageMenuSourceMock: MessageMenuSource {
    var screenFrame: CGRect?
    var windowScene: UIWindowScene? { nil }

    /// - Parameter screenFrame: кадр пузыря на экране.
    init(screenFrame: CGRect?) {
        self.screenFrame = screenFrame
    }
}
