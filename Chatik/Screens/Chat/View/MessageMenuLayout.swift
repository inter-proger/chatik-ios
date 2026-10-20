//
//  MessageMenuLayout.swift
//  Chatik
//

import CoreGraphics

/// Раскладка меню сообщения: где стоит копия пузыря и где — список действий.
///
/// Пузырь остаётся на своём месте, а список встаёт под ним. Если снизу места нет — над ним. Если нет и сверху
/// (пузырь высокий или стоит у края), пузырь поднимается ровно настолько, чтобы список поместился под ним, но не
/// выше верхней границы. По горизонтали список выровнен по краю пузыря: у своих сообщений — по правому,
/// у входящих — по левому, и не выходит за границы.
struct MessageMenuLayout: Equatable {
    /// Кадр копии пузыря.
    let bubbleFrame: CGRect
    /// Кадр списка действий.
    let menuFrame: CGRect

    /// Промежуток между пузырём и списком.
    static let spacing: CGFloat = 8

    /// - Parameters:
    ///   - bubbleFrame: кадр пузыря в ленте.
    ///   - menuSize: размер списка действий.
    ///   - bounds: область, в которой должны поместиться пузырь и список.
    ///   - isOutgoing: своё сообщение — список выровнен по правому краю пузыря.
    init(bubbleFrame: CGRect, menuSize: CGSize, bounds: CGRect, isOutgoing: Bool) {
        let x = Self.menuX(bubbleFrame: bubbleFrame, menuWidth: menuSize.width, bounds: bounds, isOutgoing: isOutgoing)
        let needed = Self.spacing + menuSize.height
        if bubbleFrame.maxY + needed <= bounds.maxY {
            self.bubbleFrame = bubbleFrame
            menuFrame = CGRect(origin: CGPoint(x: x, y: bubbleFrame.maxY + Self.spacing), size: menuSize)
        } else if bubbleFrame.minY - needed >= bounds.minY {
            self.bubbleFrame = bubbleFrame
            menuFrame = CGRect(origin: CGPoint(x: x, y: bubbleFrame.minY - needed), size: menuSize)
        } else {
            let bubbleY = max(bounds.minY, bounds.maxY - needed - bubbleFrame.height)
            self.bubbleFrame = CGRect(origin: CGPoint(x: bubbleFrame.minX, y: bubbleY), size: bubbleFrame.size)
            let menuY = min(self.bubbleFrame.maxY + Self.spacing, bounds.maxY - menuSize.height)
            menuFrame = CGRect(origin: CGPoint(x: x, y: menuY), size: menuSize)
        }
    }

    /// Левый край списка: по краю пузыря со стороны сообщения, в пределах границ.
    /// - Parameters:
    ///   - bubbleFrame: кадр пузыря.
    ///   - menuWidth: ширина списка.
    ///   - bounds: границы.
    ///   - isOutgoing: своё сообщение.
    private static func menuX(bubbleFrame: CGRect, menuWidth: CGFloat, bounds: CGRect, isOutgoing: Bool) -> CGFloat {
        let preferred = isOutgoing ? bubbleFrame.maxX - menuWidth : bubbleFrame.minX
        return min(max(preferred, bounds.minX), bounds.maxX - menuWidth)
    }
}
