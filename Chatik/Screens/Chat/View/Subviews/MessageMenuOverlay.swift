//
//  MessageMenuOverlay.swift
//  Chatik
//

import SwiftUI

/// Меню сообщения: размытый фон, копия пузыря на его месте и список действий под ним (`MessageMenuLayout`).
///
/// Копия появляется сразу на месте пузыря — подмена незаметна, — затем вместе с фоном и списком «приподнимается»:
/// тень, при нехватке места снизу сдвиг вверх. Тап мимо списка закрывает меню без выбора. С началом закрытия
/// вызывается `onClose` (пузырь в ленте возвращается, выбранное действие выполняется), копия гаснет на месте, по
/// окончании анимации — `onClosed`.
struct MessageMenuOverlay: View {
    let message: MessageDisplayModel
    /// Кадр пузыря на экране.
    let sourceFrame: CGRect
    /// Область, в которой должны поместиться копия и список.
    let bounds: CGRect
    /// Меню начало закрываться; параметр — выбранное действие.
    let onClose: (MessageAction?) -> Void
    /// Анимация закрытия закончилась.
    let onClosed: () -> Void

    /// Меню раскрыто: фон, тень и список видны.
    @State private var isShown = false
    /// Меню закрывается: повторные закрытия не принимаются.
    @State private var isClosing = false
    /// Размер списка действий; `nil` — ещё не измерен, меню не раскрывается.
    @State private var menuSize: CGSize?

    /// Ширина списка действий.
    private static let menuWidth: CGFloat = 250
    /// Высота строки списка.
    private static let rowHeight: CGFloat = 44

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            bubble
            actionsList
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape) { close(with: nil) }
    }

    /// Раскладка по измеренному списку; до измерения — по оценке.
    private var layout: MessageMenuLayout {
        let estimated = CGSize(width: Self.menuWidth, height: Self.rowHeight * CGFloat(message.actions.count))
        return MessageMenuLayout(
            bubbleFrame: sourceFrame,
            menuSize: menuSize ?? estimated,
            bounds: bounds,
            isOutgoing: message.isOutgoing
        )
    }

    /// Размытый фон: тап по нему закрывает меню.
    private var background: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(isShown ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { close(with: nil) }
            .accessibilityHidden(true)
    }

    /// Копия пузыря: в раскрытом меню — на месте из раскладки, иначе — на месте пузыря в ленте.
    private var bubble: some View {
        let frame = isShown ? layout.bubbleFrame : sourceFrame
        return MessageBubble(message: message)
            .frame(width: sourceFrame.width, height: sourceFrame.height)
            .shadow(color: .black.opacity(isShown ? 0.18 : 0), radius: 12, y: 4)
            .opacity(isClosing ? 0 : 1)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Список действий. Измеряется в первом проходе раскладки без анимации, после этого меню раскрывается.
    private var actionsList: some View {
        let frame = layout.menuFrame
        let isAbove = frame.maxY <= layout.bubbleFrame.minY
        let anchor: UnitPoint = switch (isAbove, message.isOutgoing) {
        case (false, true): .topTrailing
        case (false, false): .topLeading
        case (true, true): .bottomTrailing
        case (true, false): .bottomLeading
        }
        return VStack(spacing: 0) {
            ForEach(Array(message.actions.enumerated()), id: \.element) { index, action in
                if index > 0 {
                    Divider()
                }
                actionRow(action)
            }
        }
        .frame(width: Self.menuWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { didMeasureMenu($0) }
        .scaleEffect(isShown ? 1 : 0.5, anchor: anchor)
        .opacity(isShown ? 1 : 0)
        .position(x: frame.midX, y: frame.midY)
    }

    /// Строка списка: название слева, значок справа — как в системных меню; удаление — красным.
    /// - Parameter action: действие.
    private func actionRow(_ action: MessageAction) -> some View {
        Button {
            close(with: action)
        } label: {
            HStack {
                Text(action.title)
                Spacer(minLength: 16)
                Image(systemName: action.systemImage)
            }
            .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    /// Список измерен: размер ставится без анимации, первое измерение раскрывает меню.
    /// - Parameter size: размер списка.
    private func didMeasureMenu(_ size: CGSize) {
        let isFirst = menuSize == nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { menuSize = size }
        guard isFirst else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { isShown = true }
    }

    /// Закрывает меню: сразу сообщает о закрытии, затем сворачивает меню и гасит копию пузыря.
    /// - Parameter action: выбранное действие; `nil` — меню закрыто без выбора.
    private func close(with action: MessageAction?) {
        guard !isClosing else { return }
        isClosing = true
        onClose(action)
        withAnimation(.easeOut(duration: 0.2)) {
            isShown = false
        } completion: {
            onClosed()
        }
    }
}

/// Строка меню: при нажатии подсвечивается фоном, как в системных меню.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
    }
}
