//
//  MessageMenuWindowPresenter.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Показывает меню сообщения в отдельном окне поверх приложения: затемнение закрывает и панель навигации, а кнопка
/// «назад» под ним не нажимается.
///
/// Окно становится ключевым — VoiceOver работает с меню. С началом закрытия ключевым снова становится окно экрана:
/// выбранное «Редактировать» ставит фокус в поле ввода, и клавиатура должна подняться там. Окно меню убирается,
/// когда закончится анимация закрытия.
@MainActor
final class MessageMenuWindowPresenter: MessageMenuPresenting {
    /// Окно открытого меню.
    private var window: UIWindow?

    /// Отступ меню от краёв безопасной области.
    private static let margin: CGFloat = 8

    /// Показывает меню в новом окне той же сцены, что и пузырь.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - frame: кадр пузыря на экране.
    ///   - source: пузырь — из него берётся сцена.
    ///   - onClose: меню начало закрываться.
    func present(
        message: MessageDisplayModel,
        frame: CGRect,
        source: MessageMenuSource,
        onClose: @escaping (MessageAction?) -> Void
    ) {
        guard window == nil, let scene = source.windowScene, let sourceWindow = scene.keyWindow else { return }
        let window = UIWindow(windowScene: scene)
        let bounds = sourceWindow.bounds
            .inset(by: sourceWindow.safeAreaInsets)
            .insetBy(dx: Self.margin, dy: Self.margin)
        let overlay = MessageMenuOverlay(
            message: message,
            sourceFrame: frame,
            bounds: bounds,
            onClose: { [weak sourceWindow] action in
                sourceWindow?.makeKey()
                onClose(action)
            },
            onClosed: { [weak self] in self?.dismissWindow() }
        )
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        self.window = window
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Убирает окно меню.
    private func dismissWindow() {
        window?.isHidden = true
        window = nil
    }
}
