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
    /// Начало закрытия открытого меню; `nil` — меню нет или оно уже закрывается.
    private var close: ((MessageAction?) -> Void)?

    /// Отступ меню от краёв безопасной области.
    private static let margin: CGFloat = 8

    /// Показывает меню в новом окне той же сцены, что и пузырь.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - frame: кадр пузыря на экране.
    ///   - source: пузырь — из него берётся сцена.
    ///   - onClose: меню начало закрываться.
    /// - Returns: `false` — окно прежнего меню ещё не убрано или у сцены нет ключевого окна.
    func present(
        message: MessageDisplayModel,
        frame: CGRect,
        source: MessageMenuSource,
        onClose: @escaping (MessageAction?) -> Void
    ) -> Bool {
        guard window == nil, let scene = source.windowScene, let sourceWindow = scene.keyWindow else { return false }
        let close: (MessageAction?) -> Void = { [weak self, weak sourceWindow] action in
            self?.close = nil
            sourceWindow?.makeKey()
            onClose(action)
        }
        let overlay = MessageMenuOverlay(
            message: message,
            sourceFrame: frame,
            bounds: Self.menuBounds(in: sourceWindow),
            onClose: close,
            onClosed: { [weak self] in self?.dismissWindow() }
        )
        let window = Self.makeWindow(scene: scene, rootView: overlay)
        window.makeKeyAndVisible()
        self.window = window
        self.close = close
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }

    /// Закрывает открытое меню без анимации и без выбора.
    func dismiss() {
        guard let close else { return }
        close(nil)
        dismissWindow()
    }

    /// Убирает окно меню.
    private func dismissWindow() {
        window?.isHidden = true
        window = nil
    }

    /// Область, в которой помещаются копия пузыря и список: безопасная область окна экрана с отступом.
    /// - Parameter window: окно экрана.
    private static func menuBounds(in window: UIWindow) -> CGRect {
        window.bounds
            .inset(by: window.safeAreaInsets)
            .insetBy(dx: margin, dy: margin)
    }

    /// Создаёт прозрачное окно меню над окном экрана.
    /// - Parameters:
    ///   - scene: сцена экрана.
    ///   - rootView: содержимое меню.
    private static func makeWindow(scene: UIWindowScene, rootView: MessageMenuOverlay) -> UIWindow {
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = .normal + 1
        return window
    }
}
