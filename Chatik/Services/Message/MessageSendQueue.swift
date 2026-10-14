//
//  MessageSendQueue.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol MessageSendQueueProtocol: AuthServiceObserver {
    /// Сообщения текущего пользователя во всех переписках, ещё не подтверждённые сервером, сначала самые старые.
    var outgoingMessages: [OutgoingMessage] { get }

    /// Восстанавливает очередь из БД при старте приложения и повторяет прерванные отправки.
    func start()
    /// Ставит новое сообщение в очередь отправки.
    func enqueue(text: String, conversationId: Int)
    /// Повторяет отправку неотправленного сообщения.
    func retry(clientId: String)
    /// Удаляет неотправленное сообщение.
    func delete(clientId: String)
    /// Убирает из очереди сообщения, которые сервер уже создал.
    func removeConfirmed(by messages: [Message])
    /// Поток сообщений, созданных сервером в ответ на отправку; заканчивается, когда отменена читающая его задача.
    func sentMessages() -> AsyncStream<Message>
}

/// Очередь отправки сообщений — единая для всех переписок и не зависящая от экранов: отправка продолжается,
/// даже если чат закрыт.
///
/// Новое сообщение получает `clientId`, сразу появляется в `outgoingMessages` в статусе «отправляется» и сохраняется
/// в БД. Запросы `/messages/send` уходят по одному в порядке отправки, чтобы сообщения создавались на сервере в том
/// же порядке. Ответ сервера поднимает переписку в списке чатов (`ConversationPositionUpdating`), публикуется
/// в `sentMessages()`, убирает сообщение из очереди и сохраняется в БД
/// (неотправленная копия удаляется там же, см. `MessageStorageService`). Событие WebSocket или страница переписки
/// с тем же `clientId` тоже подтверждают доставку. При ошибке сообщение и все ждущие отправки после него переходят
/// в статус «не отправлено» — так порядок не нарушится; каждое можно отправить повторно с тем же `clientId` или
/// удалить. Сообщение, `clientId` которого сервер отклонил как занятый (6004), удаляется сразу, а очередь идёт дальше.
///
/// Очередь хранится в БД и восстанавливается при старте приложения (`start()`): отправки, прерванные закрытием
/// приложения, повторяются с тем же `clientId` — сервер не создаст дубль.
///
/// Все записи в БД идут одной последовательной цепочкой — в порядке действий. При выходе из аккаунта
/// (`authServiceWillLogout`) очередь очищается, текущий запрос отменяется, а выход дожидается начатых записей:
/// ничего не попадёт в БД после её очистки.
@MainActor
@Observable
final class MessageSendQueue: MessageSendQueueProtocol {
    private(set) var outgoingMessages: [OutgoingMessage] = []

    private let messageService: MessageServiceProtocol
    private let messageStorage: MessageStorageServiceProtocol
    private let outgoingMessageStorage: OutgoingMessageStorageServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let now: () -> Date
    private let makeClientId: () -> String

    /// `clientId` сообщений, ждущих отправки, в порядке очереди.
    private var pendingDeliveries: [String] = []
    /// Задача, отправляющая сообщения по одному; `nil` — отправлять нечего.
    private var worker: Task<Void, Never>?
    /// Последняя запись в БД: следующая начинается только после неё.
    private var lastWrite: Task<Void, Never>?
    /// Поколение очереди: выход из аккаунта его меняет, и записи, поставленные раньше, не выполняются.
    private var generation = 0
    /// `true` между `authServiceWillLogout` и `authServiceDidLogout`: новые сообщения не принимаются.
    private var isLoggingOut = false
    private var subscribers: [UUID: AsyncStream<Message>.Continuation] = [:]
    private let positionUpdater: ConversationPositionUpdating
    /// Подписка на очередь событий WebSocket — подтверждения собственных сообщений. Берётся в `init`: очередь
    /// создаётся раньше соединения, и события не пройдут мимо.
    private var eventSubscription: RealtimeSubscription?

    /// - Parameters:
    ///   - messageService: отправка `/messages/send`.
    ///   - messageStorage: куда сохраняются отправленные сообщения.
    ///   - outgoingMessageStorage: хранилище очереди в БД.
    ///   - sessionService: текущий пользователь — отправитель.
    ///   - eventQueue: очередь событий WebSocket — подтверждения собственных сообщений.
    ///   - positionUpdater: список чатов — поднимает переписку по ответу на отправку.
    ///   - now: текущее время; подменяется в тестах.
    ///   - makeClientId: генератор `clientId` новых сообщений (UUID v4); подменяется в тестах.
    init(
        messageService: MessageServiceProtocol,
        messageStorage: MessageStorageServiceProtocol,
        outgoingMessageStorage: OutgoingMessageStorageServiceProtocol,
        sessionService: SessionServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        positionUpdater: ConversationPositionUpdating,
        now: @escaping () -> Date = { Date() },
        makeClientId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.messageService = messageService
        self.messageStorage = messageStorage
        self.outgoingMessageStorage = outgoingMessageStorage
        self.sessionService = sessionService
        self.now = now
        self.makeClientId = makeClientId
        self.positionUpdater = positionUpdater
        eventSubscription = eventQueue.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - Действия

    /// Читает очередь из БД и добавляет сообщения, которых ещё нет в памяти; прерванные отправки повторяет.
    /// Во время выхода из аккаунта ничего не делает.
    func start() {
        guard !isLoggingOut else { return }
        let generation = generation
        Task {
            let stored = await loadStored()
            guard generation == self.generation else { return }
            restore(stored)
        }
    }

    /// Создаёт сообщение текущего пользователя в статусе «отправляется», сохраняет его в БД и ставит в очередь.
    /// Без сессии и во время выхода ничего не делает.
    /// - Parameters:
    ///   - text: введённый текст; краевые пробелы и невидимые символы обрезаются, как это сделает сервер.
    ///   - conversationId: переписка, в которую уходит сообщение.
    func enqueue(text: String, conversationId: Int) {
        guard !isLoggingOut, let senderId = sessionService.currentUser?.userId else { return }
        let message = OutgoingMessage(
            clientId: makeClientId(),
            conversationId: conversationId,
            senderId: senderId,
            text: text.trimmingCharacters(in: MessageTextValidator.trimmedCharacters),
            createdAt: now(),
            status: .sending
        )
        outgoingMessages.append(message)
        store(message)
        scheduleDelivery(clientId: message.clientId)
    }

    /// Повторяет отправку неотправленного сообщения с тем же `clientId`: если прошлый запрос всё-таки дошёл,
    /// сервер вернёт уже созданное сообщение.
    /// - Parameter clientId: идентификатор сообщения.
    func retry(clientId: String) {
        guard let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }),
              outgoingMessages[index].status == .failed else { return }
        outgoingMessages[index].status = .sending
        store(outgoingMessages[index])
        scheduleDelivery(clientId: clientId)
    }

    /// Удаляет неотправленное сообщение из очереди и БД.
    /// - Parameter clientId: идентификатор сообщения.
    func delete(clientId: String) {
        guard let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }),
              outgoingMessages[index].status == .failed else { return }
        outgoingMessages.remove(at: index)
        removeStored(clientId: clientId)
    }

    /// Убирает из очереди сообщения, которые сервер уже создал: совпадают отправитель и `clientId`. Из БД их
    /// неотправленные копии удаляет `MessageStorageService` при сохранении серверных сообщений.
    /// - Parameter messages: сообщения с сервера.
    func removeConfirmed(by messages: [Message]) {
        let keys = Set(messages.map(\.clientKey))
        guard outgoingMessages.contains(where: { keys.contains($0.clientKey) }) else { return }
        outgoingMessages.removeAll { keys.contains($0.clientKey) }
    }

    /// Подписывает на сообщения, созданные сервером в ответ на отправку.
    func sentMessages() -> AsyncStream<Message> {
        let (stream, continuation) = AsyncStream.makeStream(of: Message.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[id] = nil }
        }
        return stream
    }

    // MARK: - Выход из аккаунта

    /// Выход из аккаунта начинается (`AuthServiceObserver`): очередь очищается, текущий запрос отменяется,
    /// поставленные записи в БД не выполняются, а начатые дожидаются окончания — до очистки БД.
    func authServiceWillLogout() async {
        isLoggingOut = true
        generation += 1
        pendingDeliveries.removeAll()
        outgoingMessages.removeAll()
        let worker = worker
        worker?.cancel()
        await worker?.value
        await lastWrite?.value
    }

    /// Выход из аккаунта завершён (`AuthServiceObserver`): очередь снова принимает сообщения.
    /// - Parameter reason: причина выхода; на очередь не влияет.
    func authServiceDidLogout(reason: LogoutReason) async {
        isLoggingOut = false
    }

    // MARK: - Отправка

    /// Ставит отправку в конец очереди и запускает обработку, если она не идёт.
    /// - Parameter clientId: идентификатор сообщения.
    private func scheduleDelivery(clientId: String) {
        pendingDeliveries.append(clientId)
        guard worker == nil else { return }
        worker = Task { await processDeliveries() }
    }

    /// Отправляет сообщения очереди по одному, пока она не опустеет или задачу не отменят.
    private func processDeliveries() async {
        while !Task.isCancelled, !pendingDeliveries.isEmpty {
            await deliver(clientId: pendingDeliveries.removeFirst())
        }
        worker = nil
    }

    /// Отправляет сообщение на сервер. Сообщение, которое за время ожидания удалили или подтвердило событие
    /// WebSocket, не отправляется. Ответ на отменённый запрос (выход из аккаунта) не применяется.
    /// - Parameter clientId: идентификатор сообщения.
    private func deliver(clientId: String) async {
        guard let message = outgoingMessages.first(where: { $0.clientId == clientId }),
              message.status == .sending else { return }
        do {
            let sent = try await messageService.send(conversationId: message.conversationId, text: message.text, clientId: clientId)
            guard !Task.isCancelled else { return }
            confirm(sent)
        } catch {
            guard !Task.isCancelled else { return }
            handleFailure(clientId: clientId, error: error)
        }
    }

    /// Применяет ответ сервера: поднимает переписку в списке чатов, публикует сообщение подписчикам, убирает его
    /// из очереди и ставит запись в БД. Запись не ждётся — следующее сообщение отправляется сразу; неотправленная
    /// копия удаляется из БД в той же записи.
    /// - Parameter message: созданное сервером сообщение.
    private func confirm(_ message: Message) {
        positionUpdater.applySentMessage(message)
        subscribers.values.forEach { $0.yield(message) }
        removeConfirmed(by: [message])
        write("сохранить отправленное сообщение") { [messageStorage] in
            try await messageStorage.save(message: message)
        }
    }

    /// Помечает сообщение как неотправленное, а вместе с ним — все сообщения, ждущие отправки после него: иначе
    /// они ушли бы раньше упавшего, и после его повтора порядок на сервере разошёлся бы с порядком отправки.
    /// Каждое придётся отправить повторно вручную. Сообщение, `clientId` которого сервер отклонил как занятый
    /// в другой переписке (6004), удаляется: повторить его отправку нельзя, а порядок остальных оно не нарушает.
    /// - Parameters:
    ///   - clientId: идентификатор сообщения.
    ///   - error: ошибка отправки.
    private func handleFailure(clientId: String, error: Error) {
        if case NetworkError.api(code: NetworkError.Code.clientIdConflict) = error {
            guard let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }) else { return }
            outgoingMessages.remove(at: index)
            removeStored(clientId: clientId)
            return
        }
        let failedIds = [clientId] + pendingDeliveries
        pendingDeliveries.removeAll()
        markFailed(clientIds: failedIds)
    }

    /// Переводит отправляющиеся сообщения в статус «не отправлено» и сохраняет статус в БД.
    /// - Parameter clientIds: идентификаторы сообщений; удалённые и уже неотправленные пропускаются.
    private func markFailed(clientIds: [String]) {
        for clientId in clientIds {
            guard let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }),
                  outgoingMessages[index].status == .sending else { continue }
            outgoingMessages[index].status = .failed
            store(outgoingMessages[index])
        }
    }

    /// Применяет событие WebSocket: собственное сообщение с тем же `clientId` подтверждает доставку.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) {
        switch event {
        case let .messageReceived(message, _), let .messageEdited(message, _):
            removeConfirmed(by: [message])
        case .connected, .conversationCreated:
            break
        }
    }

    /// Добавляет в очередь сообщения из БД, которых ещё нет в памяти, и повторяет прерванные отправки.
    /// - Parameter stored: сообщения из БД.
    private func restore(_ stored: [OutgoingMessage]) {
        let knownIds = Set(outgoingMessages.map(\.clientId))
        let restored = stored.filter { !knownIds.contains($0.clientId) }
        guard !restored.isEmpty else { return }
        outgoingMessages = (outgoingMessages + restored).sorted { $0.createdAt < $1.createdAt }
        for message in restored where message.status == .sending {
            scheduleDelivery(clientId: message.clientId)
        }
    }

    // MARK: - Локальная БД

    /// Читает очередь из БД. Ошибка чтения не мешает работе — очередь останется пустой.
    private func loadStored() async -> [OutgoingMessage] {
        do {
            return try await outgoingMessageStorage.fetchAll()
        } catch {
            Logger.storage.error("Не удалось прочитать очередь отправки из БД: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Сохраняет сообщение очереди в БД.
    /// - Parameter message: сообщение с актуальным статусом.
    private func store(_ message: OutgoingMessage) {
        write("сохранить сообщение очереди") { [outgoingMessageStorage] in
            try await outgoingMessageStorage.save(message: message)
        }
    }

    /// Удаляет сообщение очереди из БД.
    /// - Parameter clientId: идентификатор сообщения.
    private func removeStored(clientId: String) {
        write("удалить сообщение очереди") { [outgoingMessageStorage] in
            try await outgoingMessageStorage.delete(clientId: clientId)
        }
    }

    /// Ставит запись в БД в конец цепочки. Запись, поставленная до выхода из аккаунта, не выполняется.
    /// Ошибка записи не мешает работе очереди, но логируется.
    /// - Parameters:
    ///   - action: что делает запись — для лога.
    ///   - operation: запись.
    /// - Returns: задача записи — чтобы дождаться её.
    @discardableResult
    private func write(_ action: String, _ operation: @escaping () async throws -> Void) -> Task<Void, Never> {
        let previous = lastWrite
        let generation = generation
        let task = Task {
            await previous?.value
            guard generation == self.generation else { return }
            do {
                try await operation()
            } catch {
                Logger.storage.error("Очередь отправки: не удалось \(action, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        lastWrite = task
        return task
    }
}
