//
//  MessageContextMenu.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Состояние меню по долгому нажатию на пузырь.
enum MessageMenuPhase: Equatable {
    /// Меню нет.
    case closed
    /// Пузырь нажат: идёт подсветка, меню ещё не открылось и может не открыться (палец отпущен раньше).
    case pressed
    /// Меню открыто: пузырь скрыт, на его месте превью.
    case open
    /// Меню закрывается: пузырь уже виден, а View меню ещё нужна анимации закрытия.
    case closing
}

/// Меню по долгому нажатию на пузырь — на `UIContextMenuInteraction`, а не на SwiftUI `contextMenu`.
///
/// Лента перевёрнута (`flippedVertically` у прокрутки и у строк). SwiftUI `contextMenu` анимирует снимок пузыря
/// из контейнера внутри перевёрнутой прокрутки в окно и обратно, и на переходах пузырь на несколько кадров
/// переворачивается или сплющивается. Здесь превью — снимок пузыря с экрана, как его видит пользователь, а точка
/// подсветки задана в координатах окна: в анимациях перевёрнутых контейнеров нет.
///
/// Ставится поверх пузыря (`overlay`) и принимает касания: долгое нажатие — меню, прокрутка — у прокрутки
/// (её жест висит на предке), тап проходит дальше по цепочке жестов предков. Пока меню открыто (`phase == .open`),
/// сам пузырь нужно скрыть: превью — снимок, и без этого под затемнением был бы виден второй пузырь.
struct MessageContextMenu: UIViewRepresentable {
    /// Пункты меню; пусто — меню не открывается.
    let actions: [MessageAction]
    /// Радиус скругления пузыря — по нему обрезается снимок в превью.
    let cornerRadius: CGFloat
    /// Состояние меню — по нему пузырь скрывается, а эта View остаётся до конца анимации закрытия.
    @Binding var phase: MessageMenuPhase
    /// Выбран пункт меню.
    let onAction: (MessageAction) -> Void

    func makeUIView(context: Context) -> MessageContextMenuView {
        let view = MessageContextMenuView()
        view.backgroundColor = .clear
        view.addInteraction(UIContextMenuInteraction(delegate: view))
        return view
    }

    func updateUIView(_ view: MessageContextMenuView, context: Context) {
        view.actions = actions
        view.cornerRadius = cornerRadius
        view.onAction = onAction
        view.onPhaseChange = { phase = $0 }
    }
}

/// View с `UIContextMenuInteraction`: собирает меню из `actions` и превью — снимок своей области экрана.
final class MessageContextMenuView: UIView, UIContextMenuInteractionDelegate {
    var actions: [MessageAction] = []
    var cornerRadius: CGFloat = 0
    var onAction: (MessageAction) -> Void = { _ in }
    var onPhaseChange: (MessageMenuPhase) -> Void = { _ in }
    /// Снимок пузыря на момент нажатия: показывается в подсветке, в меню и при закрытии.
    private var snapshot: UIView?

    // MARK: - UIContextMenuInteractionDelegate

    /// Меню из пунктов `actions`; без пунктов меню нет.
    /// - Parameters:
    ///   - interaction: взаимодействие.
    ///   - location: точка нажатия.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !actions.isEmpty else { return nil }
        let actions = actions
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: actions.map { action in
                UIAction(title: Self.title(of: action), image: UIImage(systemName: Self.imageName(of: action))) { _ in
                    self?.onAction(action)
                }
            })
        }
    }

    /// Превью подсветки при нажатии: снимок пузыря с экрана, поставленный в окно на место пузыря. Окно
    /// не отражено, поэтому ни подсветка, ни открытие меню не проходят через переворот.
    /// - Parameters:
    ///   - interaction: взаимодействие.
    ///   - configuration: конфигурация меню.
    ///   - identifier: идентификатор пункта; у меню одного пузыря не используется.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        onPhaseChange(.pressed)
        snapshot = makeSnapshot()
        guard let window else { return nil }
        let frame = convert(bounds, to: window)
        return targetedPreview(in: window, center: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Превью закрытия не задаётся: снимок растворяется там, где стоит, — на месте пузыря, а пузырь
    /// показывается сразу (`willEndFor`). Перелёт снимка к пузырю не нужен: превью не сдвигается с места
    /// пузыря, а после выбора «Редактировать» лента уезжает, и снимок прилетел бы туда, где пузыря уже нет.
    /// - Parameters:
    ///   - interaction: взаимодействие.
    ///   - configuration: конфигурация меню.
    ///   - identifier: идентификатор пункта; у меню одного пузыря не используется.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        nil
    }

    /// Меню открывается: пузырь скрывается, на его месте превью.
    /// - Parameters:
    ///   - interaction: взаимодействие.
    ///   - configuration: конфигурация меню.
    ///   - animator: анимация открытия.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        onPhaseChange(.open)
    }

    /// Меню закрывается — или подсветка отменена, не дойдя до меню: пузырь показывается сразу, пока снимок
    /// растворяется на его месте. Ждать окончания
    /// анимации нельзя: система сообщает о нём с задержкой (почти на секунду позже, чем исчезает снимок), и всё
    /// это время на месте пузыря была бы пустота. Окончание закрытия не зависит от этой View: выбранное действие
    /// может убрать меню у пузыря (в режиме редактирования действий нет).
    /// - Parameters:
    ///   - interaction: взаимодействие.
    ///   - configuration: конфигурация меню.
    ///   - animator: анимация закрытия; `nil` — закрытие без анимации.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        let onPhaseChange = onPhaseChange
        let finish = { [weak self] in
            onPhaseChange(.closed)
            self?.snapshot = nil
        }
        guard let animator else {
            finish()
            return
        }
        onPhaseChange(.closing)
        animator.addCompletion(finish)
    }

    // MARK: - Превью

    /// Снимок области экрана под этой View — пузырь таким, каким его видит пользователь, без отражений.
    private func makeSnapshot() -> UIView? {
        guard let window else { return nil }
        let frame = convert(bounds, to: window)
        return window.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero)
    }

    /// Превью со снимком пузыря, поставленное в контейнер.
    /// - Parameters:
    ///   - container: View, в которой стоит превью.
    ///   - center: центр превью в координатах контейнера.
    /// - Returns: `nil` — View уже не на экране или снимка нет: система обойдётся без анимации превью.
    private func targetedPreview(in container: UIView, center: CGPoint) -> UITargetedPreview? {
        guard window != nil, let snapshot else { return nil }
        snapshot.bounds = CGRect(origin: .zero, size: bounds.size)
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: snapshot.bounds, cornerRadius: cornerRadius)
        let target = UIPreviewTarget(container: container, center: center)
        return UITargetedPreview(view: snapshot, parameters: parameters, target: target)
    }

    /// Название пункта меню.
    /// - Parameter action: действие.
    private static func title(of action: MessageAction) -> String {
        switch action {
        case .edit: ChatStrings.messageActionEdit
        }
    }

    /// Значок пункта меню (SF Symbol).
    /// - Parameter action: действие.
    private static func imageName(of action: MessageAction) -> String {
        switch action {
        case .edit: "pencil"
        }
    }
}
