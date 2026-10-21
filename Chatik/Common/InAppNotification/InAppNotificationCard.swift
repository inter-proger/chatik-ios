//
//  InAppNotificationCard.swift
//  Chatik
//

import SwiftUI

/// Карточка уведомления с жестами как у системных пушей: касание ставит таймер на паузу, свайп вверх скрывает,
/// нажатие выполняет действие уведомления и скрывает его.
struct InAppNotificationCard: View {
    let notification: InAppNotification
    let service: any InAppNotificationServiceProtocol

    /// Сдвиг карточки за пальцем.
    @State private var offset: CGFloat = 0
    /// Карточку скрыли жестом: она уезжает с текущего места, а не возвращается.
    @State private var isDismissing = false
    /// Палец на карточке. Сбрасывается и при отмене жеста системой, когда `onEnded` не вызывается.
    @GestureState private var isTouching = false

    /// Насколько увести карточку вверх, чтобы при отпускании она скрылась.
    private static let dismissDistance: CGFloat = 30
    /// Насколько вверх должно продолжиться движение после отпускания, чтобы считаться резким свайпом.
    private static let dismissPredictedDistance: CGFloat = 100
    /// Сдвиг, до которого отпускание считается нажатием.
    private static let tapTolerance: CGFloat = 10
    /// Сопротивление движению вниз: карточка проходит эту долю пути пальца.
    private static let downwardResistance: CGFloat = 0.2

    var body: some View {
        content
            .offset(y: offset)
            .contentShape(.rect)
            .gesture(dragGesture)
            .onChange(of: isTouching) { _, isTouching in
                didChangeTouching(isTouching)
            }
            .accessibilityElement(children: .combine)
            .modifier(TapAccessibilityAction(onTap: notification.onTap.map { _ in didTap }))
            .accessibilityAction(.escape, dismiss)
            .accessibilityAction(named: InAppNotificationStrings.dismissAction, dismiss)
    }

    /// View вида уведомления.
    @ViewBuilder
    private var content: some View {
        switch notification.content {
        case .error(let message):
            ErrorNotificationView(message: message)
        case .message(let model):
            MessageNotificationView(model: model)
        }
    }

    /// Один жест на все действия: пауза, ведение, свайп и нажатие.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, isTouching, _ in
                isTouching = true
            }
            .onChanged { value in
                let translation = value.translation.height
                offset = translation < 0 ? translation : translation * Self.downwardResistance
            }
            .onEnded(didEndDrag)
    }

    /// Касание началось — таймер на паузе; закончилось или отменено — таймер заново на полное время.
    /// После скрытия уведомления `resumeTimer` ничего не делает.
    /// - Parameter isTouching: палец на карточке.
    private func didChangeTouching(_ isTouching: Bool) {
        guard isTouching else {
            service.resumeTimer(id: notification.id)
            guard !isDismissing else { return }
            withAnimation(.spring) { offset = 0 }
            return
        }
        service.pauseTimer(id: notification.id)
    }

    /// Отпускание: свайп вверх скрывает карточку, почти неподвижное касание — нажатие, иначе карточка возвращается.
    /// - Parameter value: итог жеста.
    private func didEndDrag(_ value: DragGesture.Value) {
        let translation = value.translation
        let isSwipeUp = translation.height < -Self.dismissDistance
            || value.predictedEndTranslation.height < -Self.dismissPredictedDistance
        if isSwipeUp {
            dismiss()
        } else if abs(translation.width) < Self.tapTolerance, abs(translation.height) < Self.tapTolerance {
            didTap()
        }
    }

    /// Нажатие: у уведомления с действием — действие и скрытие; без действия — ничего.
    private func didTap() {
        guard let onTap = notification.onTap else { return }
        dismiss()
        onTap()
    }

    /// Скрывает карточку: она уезжает с текущего места.
    private func dismiss() {
        isDismissing = true
        service.dismiss(id: notification.id)
    }
}

/// Действие VoiceOver по умолчанию — только у уведомлений с действием по нажатию.
private struct TapAccessibilityAction: ViewModifier {
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onTap {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, onTap)
        } else {
            content
        }
    }
}
