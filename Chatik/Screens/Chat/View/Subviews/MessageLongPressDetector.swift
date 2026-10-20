//
//  MessageLongPressDetector.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Источник меню сообщения: пузырь, по которому долго нажали (или тапнули по неотправленному).
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
///
/// С `opensOnTap` меню открывает и тап (неотправленное сообщение). Его тоже распознаёт UIKit: касание пузыря получает
/// эта View, и жест SwiftUI на предке пузыря до тапа не доходит. Тап распознаётся, только когда не распознано долгое
/// нажатие, — одно касание не запрашивает меню дважды.
///
/// View может быть шире пузыря слева на `leadingHitInset` — область касания значка у пузыря. Кадр источника меню —
/// кадр пузыря, без этой полосы.
struct MessageLongPressDetector: UIViewRepresentable {
    /// Меню открывает и тап, а не только долгое нажатие.
    var opensOnTap = false
    /// Ширина полосы слева от пузыря, которая тоже принимает касания.
    var leadingHitInset: CGFloat = 0
    /// Сюда записывается View — источник меню для вызова не жестом (действие VoiceOver).
    var sourceReference: MessageMenuSourceReference?
    /// Долгое нажатие или, с `opensOnTap`, тап распознаны.
    let onMenuRequest: (MessageMenuSource) -> Void

    func makeUIView(context: Context) -> MessageLongPressView {
        let view = MessageLongPressView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: MessageLongPressView, context: Context) {
        view.onMenuRequest = onMenuRequest
        view.opensOnTap = opensOnTap
        view.leadingHitInset = leadingHitInset
        sourceReference?.source = view
    }
}

/// Слабая ссылка на источник меню пузыря: меню можно открыть не только жестом, но и действием VoiceOver.
@MainActor
final class MessageMenuSourceReference {
    weak var source: MessageMenuSource?
}

/// View с распознавателями долгого нажатия и тапа; сообщает себя как источник меню.
final class MessageLongPressView: UIView, MessageMenuSource {
    var onMenuRequest: (MessageMenuSource) -> Void = { _ in }
    /// Тап открывает меню; иначе распознаватель тапа выключен и тап доходит до жестов SwiftUI выше.
    var opensOnTap: Bool {
        get { tapRecognizer.isEnabled }
        set { tapRecognizer.isEnabled = newValue }
    }
    /// Полоса слева, не входящая в кадр пузыря.
    var leadingHitInset: CGFloat = 0

    private let longPressRecognizer = UILongPressGestureRecognizer()
    private let tapRecognizer = UITapGestureRecognizer()

    /// Сколько держать палец, чтобы открылось меню.
    private static let minimumPressDuration: TimeInterval = 0.4

    override init(frame: CGRect) {
        super.init(frame: frame)
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.minimumPressDuration = Self.minimumPressDuration
        addGestureRecognizer(longPressRecognizer)
        tapRecognizer.addTarget(self, action: #selector(handleTap(_:)))
        tapRecognizer.isEnabled = false
        tapRecognizer.delegate = self
        // Тап ждёт провала долгого нажатия. Задержки нет: долгое нажатие проваливается, как только палец отпустили
        // раньше `minimumPressDuration`.
        tapRecognizer.require(toFail: longPressRecognizer)
        addGestureRecognizer(tapRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    var screenFrame: CGRect? {
        guard let window else { return nil }
        let bubbleBounds = bounds.inset(by: UIEdgeInsets(top: 0, left: leadingHitInset, bottom: 0, right: 0))
        return window.convert(convert(bubbleBounds, to: window), to: nil)
    }

    var windowScene: UIWindowScene? {
        window?.windowScene
    }

    /// Сообщает о долгом нажатии в момент распознавания, не дожидаясь, пока палец отпустят.
    /// - Parameter recognizer: распознаватель долгого нажатия.
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onMenuRequest(self)
    }

    /// Сообщает о тапе, если тап открывает меню.
    /// - Parameter recognizer: распознаватель тапа.
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onMenuRequest(self)
    }
}

extension MessageLongPressView: UIGestureRecognizerDelegate {
    /// Тап распознаётся вместе с жестами SwiftUI: иначе тап ленты (он убирает клавиатуру) забирает касание себе,
    /// и тап по неотправленному сообщению не открывает меню. Клавиатуру меню всё равно прячет само. С распознавателями
    /// этой View одновременности нет: тап и долгое нажатие одного касания исключают друг друга.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer.view !== self
    }
}
