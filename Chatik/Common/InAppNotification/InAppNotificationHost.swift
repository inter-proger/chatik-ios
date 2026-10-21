//
//  InAppNotificationHost.swift
//  Chatik
//

import SwiftUI

/// Содержимое окна уведомлений сцены: текущее уведомление сервиса под статус-баром, если эта сцена — сцена показа.
///
/// Смена уведомлений идёт в одной транзакции: прежняя карточка уезжает вверх и гаснет, новая выезжает поверх неё.
/// Смена сцены показа (уход из активного приложения) убирает карточку без анимации. Кадр карточки сообщается
/// окну — касания мимо неё проходят в экран под окном.
struct InAppNotificationHost: View {
    let service: any InAppNotificationServiceProtocol
    /// Сцена окна: карточка рисуется, только пока она — сцена показа.
    let sceneId: UUID
    /// Кадр карточки в координатах окна; `.zero` — карточки нет.
    let onCardFrameChange: (CGRect) -> Void

    /// Отступ карточки от краёв безопасной области.
    private static let margin: CGFloat = 8
    /// Наибольшая ширина карточки — на iPad она не растягивается на весь экран.
    private static let maxCardWidth: CGFloat = 500
    /// Длительность анимации появления и ухода карточки.
    static let animationDuration: TimeInterval = 0.4

    var body: some View {
        let isPresentingScene = service.presentingSceneId == sceneId
        let current = isPresentingScene ? service.current : nil
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if let current {
                    card(for: current, topInset: proxy.safeAreaInsets.top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .animation(isPresentingScene ? .spring(duration: Self.animationDuration) : nil, value: current?.id)
        .sensoryFeedback(trigger: current?.id) { _, newId in
            newId == nil ? nil : current?.feedback
        }
        .onChange(of: current?.id) {
            didChangeNotification(current)
        }
    }

    /// Карточка уведомления: отступ сверху включает статус-бар, поэтому при уходе вверх она скрывается целиком.
    /// - Parameters:
    ///   - notification: уведомление.
    ///   - topInset: верхняя безопасная область.
    private func card(for notification: InAppNotification, topInset: CGFloat) -> some View {
        InAppNotificationCard(notification: notification, service: service)
            .frame(maxWidth: Self.maxCardWidth)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                // Уходящая карточка ещё двигается, но касания принимает только показанная.
                guard service.current?.id == notification.id else { return }
                onCardFrameChange(frame)
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, topInset + Self.margin)
            .id(notification.id)
            .zIndex(notification.createdAt)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Новое уведомление объявляется VoiceOver; без уведомления касания снова проходят насквозь.
    /// - Parameter current: показанное уведомление; `nil` — уведомление скрыто.
    private func didChangeNotification(_ current: InAppNotification?) {
        guard let current else {
            onCardFrameChange(.zero)
            return
        }
        AccessibilityNotification.Announcement(Self.announcement(for: current.content)).post()
    }

    /// Текст объявления VoiceOver для вида уведомления.
    /// - Parameter content: содержимое уведомления.
    private static func announcement(for content: InAppNotification.Content) -> String {
        switch content {
        case .error(let message):
            message
        case .message(let model):
            InAppNotificationStrings.messageAnnouncement(title: model.title, text: String(model.text.characters))
        }
    }
}
