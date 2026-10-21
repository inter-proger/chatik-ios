//
//  MessageNotificationService.swift
//  Chatik
//

import Foundation
import os

/// Уведомления о новых сообщениях в неоткрытых переписках.
@MainActor
protocol MessageNotificationServiceProtocol: AuthServiceObserver {
    /// Подписывается на очередь событий. Вызывается после `conversationList.start()`; повторный вызов ничего не делает.
    func start()
    /// Переписка открылась: уведомление о ней скрывается, подготовка уведомления о ней отменяется.
    /// - Parameter conversationId: открывшаяся переписка.
    func conversationDidOpen(_ conversationId: Int)
}

/// Решает, показывать ли уведомление о новом сообщении, и собирает его. Показывает — `InAppNotificationService`,
/// открывает переписку по нажатию — `ConversationNavigator`.
///
/// **Порядок подписки.** Сервис подписывается на очередь после списка переписок: очередь доставляет событие
/// подписчикам по порядку и ждёт каждого, поэтому к обработке здесь переписка из события уже в списке — и та,
/// которую список загрузил через `getBatch`.
///
/// **Обработчик ничего не ждёт.** Он отсекает правки, свои сообщения и открытые переписки и передаёт сообщение
/// в подготовку — отдельную задачу. Ожидание отправителя внутри обработчика остановило бы очередь для всех.
///
/// **Подготовка — «последнее побеждает».** Новое сообщение отменяет подготовку прежнего: показано будет всё равно
/// только последнее, а параллельные подготовки показали бы сообщения не по порядку. Отправитель, которого нет
/// в кэше, ждётся не дольше `userWaitTimeout`, затем уведомление показывается с заглушкой вместо имени.
@MainActor
final class MessageNotificationService: MessageNotificationServiceProtocol {
    /// Сколько ждать загрузки отправителя, прежде чем показать уведомление с заглушкой.
    static let userWaitTimeout: Duration = .seconds(1)

    private let eventQueue: RealtimeEventQueueProtocol
    private let sessionService: SessionServiceProtocol
    private let conversationList: ConversationListServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let navigator: ConversationNavigating
    private let notifications: InAppNotificationServiceProtocol
    private let sleep: @Sendable (Duration) async throws -> Void
    private var subscription: RealtimeSubscription?
    /// Подготовка уведомления о последнем сообщении.
    private var preparation: Task<Void, Never>?
    /// Переписка, уведомление о которой готовится.
    private var preparingConversationId: Int?

    /// - Parameters:
    ///   - eventQueue: очередь событий WebSocket.
    ///   - sessionService: текущий пользователь — его сообщения уведомлений не дают.
    ///   - conversationList: переписка сообщения.
    ///   - userCache: отправитель.
    ///   - navigator: открытые переписки и открытие по нажатию.
    ///   - notifications: показ уведомлений.
    ///   - sleep: ожидание тайм-аута отправителя; подменяется в тестах.
    init(
        eventQueue: RealtimeEventQueueProtocol,
        sessionService: SessionServiceProtocol,
        conversationList: ConversationListServiceProtocol,
        userCache: UserCacheServiceProtocol,
        navigator: ConversationNavigating,
        notifications: InAppNotificationServiceProtocol,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.eventQueue = eventQueue
        self.sessionService = sessionService
        self.conversationList = conversationList
        self.userCache = userCache
        self.navigator = navigator
        self.notifications = notifications
        self.sleep = sleep
    }

    /// Подписывается на очередь событий; подписка живёт, пока жив сервис, и переживает выход из аккаунта.
    func start() {
        guard subscription == nil else { return }
        subscription = eventQueue.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    /// Скрывает уведомление о переписке и отменяет подготовку уведомления о ней.
    /// - Parameter conversationId: открывшаяся переписка.
    func conversationDidOpen(_ conversationId: Int) {
        if preparingConversationId == conversationId {
            cancelPreparation()
        }
        guard let current = notifications.current,
              case let .message(model) = current.content,
              model.conversationId == conversationId else { return }
        notifications.dismiss(id: current.id)
    }

    /// Выход из аккаунта: подготовка отменяется. Показанное уведомление убирает сервис уведомлений.
    func authServiceWillLogout() async {
        cancelPreparation()
    }

    /// Отсекает всё, кроме нового чужого сообщения в неоткрытой переписке, и запускает подготовку. Не ждёт.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) {
        guard case let .messageReceived(message, _, _) = event else { return }
        guard let userId = sessionService.currentUser?.userId, message.senderId != userId else { return }
        guard !navigator.isConversationOpen(message.conversationId) else { return }
        cancelPreparation()
        preparingConversationId = message.conversationId
        preparation = Task { [weak self] in
            await self?.prepare(message)
        }
    }

    /// Дожидается отправителя и показывает уведомление, если переписка всё ещё не открыта.
    /// - Parameter message: новое сообщение.
    private func prepare(_ message: Message) async {
        await waitForSender(message.senderId)
        guard !Task.isCancelled else { return }
        preparingConversationId = nil
        let conversationId = message.conversationId
        guard !navigator.isConversationOpen(conversationId) else { return }
        guard let conversation = conversationList.conversations.first(where: { $0.conversationId == conversationId }) else {
            Logger.messageNotification.error("Нет переписки \(conversationId, privacy: .public) для уведомления о сообщении")
            return
        }
        let model = MessageNotificationDisplayModel(message: message, conversation: conversation, sender: userCache.user(id: message.senderId))
        notifications.show(InAppNotification(content: .message(model), onTap: { [navigator] in
            navigator.openConversation(id: conversationId)
        }))
    }

    /// Ждёт загрузки отправителя, которого нет в кэше, но не дольше `userWaitTimeout`. Загрузка не отменяется ни по
    /// тайм-ауту, ни при отмене подготовки: её ждут и другие (список, лента), а результат останется в кэше.
    /// - Parameter senderId: отправитель.
    private func waitForSender(_ senderId: Int) async {
        guard userCache.user(id: senderId) == .pending else { return }
        let (signal, continuation) = AsyncStream<Void>.makeStream()
        Task { [userCache] in
            await userCache.loadUsers(ids: [senderId])
            continuation.yield()
        }
        let timeout = Task { [sleep] in
            try? await sleep(Self.userWaitTimeout)
            continuation.yield()
        }
        defer {
            timeout.cancel()
            continuation.finish()
        }
        for await _ in signal {
            break
        }
    }

    /// Отменяет подготовку уведомления.
    private func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
        preparingConversationId = nil
    }
}

extension Logger {
    /// Лог уведомлений о новых сообщениях.
    static let messageNotification = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "MessageNotification")
}
