//
//  MessageMenuController.swift
//  Chatik
//

import Foundation
import Observation

/// Показ меню сообщения.
@MainActor
protocol MessageMenuPresenting: AnyObject {
    /// Показывает меню над экраном.
    /// - Parameters:
    ///   - message: сообщение, по которому открыто меню.
    ///   - frame: кадр пузыря на экране — копия пузыря в меню встаёт на это место.
    ///   - source: пузырь — из него берётся сцена.
    ///   - onClose: меню начало закрываться; параметр — выбранное действие, `nil` — меню закрыто без выбора.
    func present(
        message: MessageDisplayModel,
        frame: CGRect,
        source: MessageMenuSource,
        onClose: @escaping (MessageAction?) -> Void
    )
}

/// Меню сообщения по долгому нажатию: показывается, когда клавиатура уже спрятана.
///
/// Открытое меню закрывает клавиатуру, и если показать его сразу, лента уезжает вниз вслед за ней, а сообщение
/// оказывается не под своей копией в меню. Поэтому при открытой клавиатуре контроллер сначала прячет её и показывает
/// меню только после `keyboardDidHide` — в кадре пузыря, где он оказался после сдвига ленты. Если событие не пришло
/// за `keyboardWaitLimit`, меню всё равно показывается — с текущим кадром.
///
/// Пока меню открыто, `menuMessageId` указывает на сообщение: лента скрывает его пузырь, на его месте копия. С началом
/// закрытия пузырь возвращается, а выбранное действие передаётся экрану.
@MainActor
@Observable
final class MessageMenuController {
    /// Меню, ждущее, пока спрячется клавиатура.
    private struct PendingMenu {
        let id: UUID
        let message: MessageDisplayModel
        let source: MessageMenuSource
        let onAction: (MessageAction) -> Void
    }

    /// Сообщение, для которого открыто меню; `nil` — меню нет.
    private(set) var menuMessageId: MessageClientKey?
    @ObservationIgnored private var isKeyboardVisible = false
    @ObservationIgnored private var pending: PendingMenu?
    @ObservationIgnored private let presenter: MessageMenuPresenting
    @ObservationIgnored private let sleep: (Duration) async throws -> Void

    /// Сколько ждать, пока спрячется клавиатура, прежде чем показать меню без неё.
    static let keyboardWaitLimit: Duration = .milliseconds(600)

    /// - Parameters:
    ///   - presenter: показ меню.
    ///   - sleep: пауза ожидания клавиатуры; подменяется в тестах.
    init(
        presenter: MessageMenuPresenting,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.presenter = presenter
        self.sleep = sleep
    }

    /// Долгое нажатие на пузырь: показывает меню сразу или, если открыта клавиатура, прячет её и ждёт.
    /// Пока меню открыто или ждёт клавиатуру, новые нажатия не принимаются.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - source: пузырь.
    ///   - hideKeyboard: прячет клавиатуру — снимает фокус с поля ввода.
    ///   - onAction: выбрано действие меню.
    func request(
        message: MessageDisplayModel,
        source: MessageMenuSource,
        hideKeyboard: () -> Void,
        onAction: @escaping (MessageAction) -> Void
    ) {
        guard menuMessageId == nil, pending == nil, !message.actions.isEmpty else { return }
        guard isKeyboardVisible else {
            present(message: message, source: source, onAction: onAction)
            return
        }
        let id = UUID()
        pending = PendingMenu(id: id, message: message, source: source, onAction: onAction)
        hideKeyboard()
        Task { [weak self, sleep] in
            try? await sleep(Self.keyboardWaitLimit)
            self?.presentPending(id: id)
        }
    }

    /// Клавиатура начала появляться.
    func keyboardWillShow() {
        isKeyboardVisible = true
    }

    /// Клавиатура начала прятаться.
    func keyboardWillHide() {
        isKeyboardVisible = false
    }

    /// Клавиатура спряталась: ждущее меню показывается.
    func keyboardDidHide() {
        guard let pending else { return }
        presentPending(id: pending.id)
    }

    /// Показывает ждущее меню, если оно ещё ждёт.
    /// - Parameter id: меню, которое должно быть показано.
    private func presentPending(id: UUID) {
        guard let pending, pending.id == id else { return }
        self.pending = nil
        present(message: pending.message, source: pending.source, onAction: pending.onAction)
    }

    /// Показывает меню над пузырём, если он ещё на экране, и скрывает пузырь в ленте.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - source: пузырь.
    ///   - onAction: выбрано действие меню.
    private func present(message: MessageDisplayModel, source: MessageMenuSource, onAction: @escaping (MessageAction) -> Void) {
        guard let frame = source.screenFrame else { return }
        menuMessageId = message.id
        presenter.present(message: message, frame: frame, source: source) { [weak self] action in
            self?.menuMessageId = nil
            guard let action else { return }
            onAction(action)
        }
    }
}
