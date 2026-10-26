//
//  ConversationNavigator.swift
//  Chatik
//

import Foundation

/// Роутер сцены, умеющий открыть переписку.
@MainActor
protocol ConversationOpening: AnyObject {
    /// Переписка, открытая первой поверх списка; `nil` — не открыта.
    var openedConversationId: Int? { get }
    /// Открывает переписку с любого экрана: закрывает лист и заменяет стек.
    /// - Parameter conversation: переписка.
    func openConversation(_ conversation: Conversation)
    /// Закрывает экраны переписки (и листы поверх них), если они есть в стеке: стек сбрасывается к списку.
    /// - Parameter conversationId: переписка.
    /// - Returns: `true` — экраны переписки были открыты.
    @discardableResult
    func closeConversation(id conversationId: Int) -> Bool
}

/// Реестр роутеров списка чатов по сценам: какая переписка где открыта и где открыть переписку из уведомления.
@MainActor
protocol ConversationNavigating: AnyObject {
    /// Регистрирует роутер сцены; роутер держится слабо.
    /// - Parameters:
    ///   - router: роутер списка чатов.
    ///   - sceneId: сцена роутера; `nil` — неизвестна (превью).
    /// - Returns: токен для снятия регистрации.
    func register(_ router: ConversationOpening, sceneId: UUID?) -> UUID
    /// Снимает регистрацию; неизвестный токен ничего не делает.
    /// - Parameter token: токен из `register`.
    func unregister(_ token: UUID)
    /// Открыта ли переписка хотя бы в одной видимой (активной) сцене.
    /// - Parameter conversationId: переписка.
    func isConversationOpen(_ conversationId: Int) -> Bool
    /// Открывает переписку в сцене показа уведомлений, а если её роутера нет — в последнем зарегистрированном.
    /// Переписки нет в списке — ничего не делает.
    /// - Parameter id: переписка.
    func openConversation(id: Int)
}

/// Реестр роутеров списка чатов. На iPad у каждой сцены свой `ChatListRootView` и свой роутер, а уведомления общие:
/// уведомление не показывается о переписке, открытой в любой активной сцене (в Split View видны обе), а нажатие
/// открывает переписку в сцене, где уведомление показано. Свёрнутая сцена остаётся зарегистрированной (`onDisappear`
/// при уходе в фон не вызывается), но переписка в ней пользователю не видна — уведомления о ней не глушит.
@MainActor
final class ConversationNavigator: ConversationNavigating, ConversationRemovalObserver {
    /// Зарегистрированный роутер.
    private struct Registration {
        let token: UUID
        let sceneId: UUID?
        weak var router: ConversationOpening?
    }

    /// Регистрации в порядке регистрации.
    private var registrations: [Registration] = []
    private let notifications: InAppNotificationServiceProtocol
    private let conversationList: ConversationListServiceProtocol

    /// - Parameters:
    ///   - notifications: сервис уведомлений — сцена показа и активные сцены.
    ///   - conversationList: список переписок — переписка по id в момент нажатия.
    init(notifications: InAppNotificationServiceProtocol, conversationList: ConversationListServiceProtocol) {
        self.notifications = notifications
        self.conversationList = conversationList
    }

    /// Регистрирует роутер сцены.
    /// - Parameters:
    ///   - router: роутер списка чатов.
    ///   - sceneId: сцена роутера.
    /// - Returns: токен для снятия регистрации.
    func register(_ router: ConversationOpening, sceneId: UUID?) -> UUID {
        let token = UUID()
        registrations.append(Registration(token: token, sceneId: sceneId, router: router))
        return token
    }

    /// Снимает регистрацию. Токен, а не сцена: появление нового корня может прийти раньше исчезновения старого.
    /// - Parameter token: токен из `register`.
    func unregister(_ token: UUID) {
        registrations.removeAll { $0.token == token }
    }

    /// Открыта ли переписка хотя бы в одном живом роутере активной сцены. Роутер без сцены (превью) считается видимым.
    /// - Parameter conversationId: переписка.
    func isConversationOpen(_ conversationId: Int) -> Bool {
        registrations.contains { registration in
            guard registration.router?.openedConversationId == conversationId else { return false }
            guard let sceneId = registration.sceneId else { return true }
            return notifications.isSceneActive(sceneId)
        }
    }

    /// Открывает переписку в роутере сцены показа уведомлений; переписка берётся из списка в момент нажатия.
    /// - Parameter id: переписка.
    func openConversation(id: Int) {
        guard let conversation = conversationList.conversations.first(where: { $0.conversationId == id }) else { return }
        let alive = registrations.filter { $0.router != nil }
        let presenting = alive.last { $0.sceneId != nil && $0.sceneId == notifications.presentingSceneId }
        (presenting ?? alive.last)?.router?.openConversation(conversation)
    }
}

extension ConversationNavigator {
    /// Пользователь больше не участник переписки: её экраны закрываются во всех сценах. Если они были открыты,
    /// а пользователь не выходил сам на этом устройстве, — уведомление «Вы больше не участник группы». Для личной
    /// переписки уведомления нет: текст про группу к ней не подходит.
    /// - Parameter info: удалённая переписка.
    func conversationWasRemoved(_ info: RemovedConversationInfo) async {
        var wasOpen = false
        for registration in registrations {
            wasOpen = (registration.router?.closeConversation(id: info.conversationId) ?? false) || wasOpen
        }
        guard wasOpen, info.reason != .left, info.type != .single else { return }
        let message = info.name.map(InAppNotificationStrings.noLongerMember(groupName:)) ?? InAppNotificationStrings.noLongerMemberUntitled
        notifications.showInfo(message)
    }
}
