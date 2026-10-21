//
//  SessionWorkLauncher.swift
//  Chatik
//

import Foundation

/// Начало работы открытой сессии с сервером — всё, что о нём знают `AppRouter` и `AuthViewModel`.
@MainActor
protocol SessionWorkStarting: AnyObject {
    /// Начинает работу открытой сессии: список переписок, отправка очереди, `/global/start`.
    func startSessionWork()
}

/// Единая точка начала работы с сервером после открытия сессии — и при восстановлении на старте, и после входа.
/// Порядок важен, поэтому он задан здесь, а не в каждом месте открытия сессии: новый путь входа не сможет его
/// нарушить или пропустить шаг.
/// 1. Список переписок читает кэш и подписывается на события: очередь событий не хранит их для будущих подписчиков.
/// 2. Уведомления о новых сообщениях подписываются после списка: к их обработке событие уже применено к списку,
///    и переписка из события есть в нём.
/// 3. Очередь отправки отправляет сообщения, прерванные прошлой сессией или закрытием приложения: ответ на отправку
///    поднимает переписку в списке, поэтому список должен быть запущен.
/// 4. `/global/start` выдаёт токен WebSocket для пользователя сессии.
@MainActor
final class SessionWorkLauncher: SessionWorkStarting {
    private let conversationList: ConversationListServiceProtocol
    private let messageNotifications: MessageNotificationServiceProtocol
    private let messageDelivery: MessageDeliveryResuming
    private let realtimeService: RealtimeServiceProtocol

    /// - Parameters:
    ///   - conversationList: список переписок; повторный запуск (вход после выхода) ничего не делает.
    ///   - messageNotifications: уведомления о новых сообщениях; повторный запуск ничего не делает.
    ///   - messageDelivery: отправка очереди — очередь загружена `SessionService` при открытии сессии.
    ///   - realtimeService: соединение с WebSocket.
    init(
        conversationList: ConversationListServiceProtocol,
        messageNotifications: MessageNotificationServiceProtocol,
        messageDelivery: MessageDeliveryResuming,
        realtimeService: RealtimeServiceProtocol
    ) {
        self.conversationList = conversationList
        self.messageNotifications = messageNotifications
        self.messageDelivery = messageDelivery
        self.realtimeService = realtimeService
    }

    /// Запускает список переписок, уведомления о сообщениях, отправку очереди и работу с сервером — в этом порядке.
    func startSessionWork() {
        conversationList.start()
        messageNotifications.start()
        messageDelivery.resumeDeliveries()
        realtimeService.start()
    }
}
