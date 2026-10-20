//
//  MessageLongPressDetector.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Источник меню сообщения: пузырь, по которому долго нажали.
@MainActor
protocol MessageMenuSource: AnyObject {
    /// Текущий кадр пузыря в координатах экрана; `nil` — пузыря уже нет на экране.
    var screenFrame: CGRect? { get }
    /// Сцена, в которой показан пузырь, — в ней же показывается меню.
    var windowScene: UIWindowScene? { get }
}

/// Распознавание долгого нажатия на пузырь — прозрачная UIKit-View поверх пузыря.
///
/// UIKit, а не SwiftUI `onLongPressGesture`: жест SwiftUI в прокрутке мешает ей начаться с пузыря. Распознаватель
/// UIKit сдаётся, как только палец сдвинулся, и прокрутку ведёт жест прокрутки (он на предке), а тап доходит до жестов
/// SwiftUI выше — лента по нему убирает клавиатуру. Сама View знает свой кадр на экране, поэтому она и есть источник
/// меню: кадр берётся в момент показа меню, после того как клавиатура спряталась и лента сдвинулась.
struct MessageLongPressDetector: UIViewRepresentable {
    /// Долгое нажатие распознано.
    let onLongPress: (MessageMenuSource) -> Void

    func makeUIView(context: Context) -> MessageLongPressView {
        let view = MessageLongPressView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: MessageLongPressView, context: Context) {
        view.onLongPress = onLongPress
    }
}

/// View с распознавателем долгого нажатия; сообщает себя как источник меню.
final class MessageLongPressView: UIView, MessageMenuSource {
    var onLongPress: (MessageMenuSource) -> Void = { _ in }

    /// Сколько держать палец, чтобы открылось меню.
    private static let minimumPressDuration: TimeInterval = 0.4

    override init(frame: CGRect) {
        super.init(frame: frame)
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = Self.minimumPressDuration
        addGestureRecognizer(recognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    var screenFrame: CGRect? {
        guard let window else { return nil }
        return window.convert(convert(bounds, to: window), to: nil)
    }

    var windowScene: UIWindowScene? {
        window?.windowScene
    }

    /// Сообщает о долгом нажатии в момент распознавания, не дожидаясь, пока палец отпустят.
    /// - Parameter recognizer: распознаватель долгого нажатия.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress(self)
    }
}
