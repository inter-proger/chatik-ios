//
//  ChatLayoutFreeze.swift
//  Chatik
//

import CoreGraphics

/// Фиксация высоты ленты и панели ввода на время меню сообщения.
///
/// Открытое меню забирает фокус у поля ввода: клавиатура прячется, лента с панелью уезжают вниз, и сообщение
/// в ленте уже не стоит под своим превью. Пока меню нажато или открыто, экран держит ту высоту, что была при
/// нажатии, — до подсветки клавиатура ещё на месте.
///
/// При закрытии меню высота отпускается:
/// - сразу, если область над клавиатурой не выше зафиксированной: клавиатура не пряталась или её не было, а
///   выбранное действие её поднимает — лента едет за ней как обычно;
/// - если клавиатура пряталась — когда она поднимется до конца (`keyboardDidShow`). Высоту над клавиатурой
///   система сообщает в начале анимации, и отпущенная в этот момент лента заходит под ещё не поднявшуюся
///   клавиатуру: прокрученная лента показывает под панелью свои сообщения и рывком прячет их;
/// - по окончании закрытия — если клавиатура так и не вернулась.
///
/// Без меню экран не фиксируется: клавиатура, поднятая тапом по полю, двигает ленту как обычно.
struct ChatLayoutFreeze: Equatable {
    /// Зафиксированная высота ленты с панелью; `nil` — экран следует за клавиатурой.
    private(set) var frozenHeight: CGFloat?
    /// Высота области экрана над клавиатурой.
    private(set) var availableHeight: CGFloat = 0
    /// Состояние меню сообщения.
    private(set) var menuPhase = MessageMenuPhase.closed
    /// Меню закрывается, а спрятанная им клавиатура ещё не поднялась до конца.
    private var isAwaitingKeyboard = false

    /// Допуск сравнения высот: доли точки после раскладки не должны держать фиксацию.
    private static let tolerance: CGFloat = 0.5

    /// Новая высота области над клавиатурой.
    /// - Parameter height: высота.
    mutating func setAvailableHeight(_ height: CGFloat) {
        availableHeight = height
        update()
    }

    /// Новое состояние меню сообщения.
    /// - Parameter phase: состояние.
    mutating func setMenuPhase(_ phase: MessageMenuPhase) {
        menuPhase = phase
        update()
    }

    /// Клавиатура поднялась до конца: высота, ждавшая её возвращения после меню, отпускается.
    mutating func keyboardDidShow() {
        guard isAwaitingKeyboard else { return }
        release()
    }

    /// Фиксирует высоту при нажатии и отпускает её при закрытии меню.
    private mutating func update() {
        switch menuPhase {
        case .pressed, .open:
            isAwaitingKeyboard = false
            guard frozenHeight == nil else { return }
            frozenHeight = availableHeight
        case .closing:
            guard let frozenHeight, !isAwaitingKeyboard else { return }
            guard availableHeight > frozenHeight + Self.tolerance else {
                release()
                return
            }
            isAwaitingKeyboard = true
        case .closed:
            release()
        }
    }

    /// Отпускает высоту: экран снова следует за клавиатурой.
    private mutating func release() {
        frozenHeight = nil
        isAwaitingKeyboard = false
    }
}
