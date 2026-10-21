//
//  MessageSendQueue.swift
//  Chatik
//

import Foundation
import os

/// Превью неотправленных сообщений для списка чатов — всё, что об очереди отправки знает `ChatListViewModel`.
@MainActor
protocol UnsentMessagePreviewProviding: AnyObject {
    /// Текст последнего неотправленного (`.failed`) сообщения переписки; `nil` — таких нет.
    /// Читается из памяти, отслеживается Observation.
    func lastFailedText(for conversationId: Int) -> String?
}

/// Запуск отправки очереди — всё, что об очереди знает `SessionWorkLauncher`.
@MainActor
protocol MessageDeliveryResuming: AnyObject {
    /// Запускает отправку очереди: загруженные из БД сообщения в статусе «отправляется», затем поставленные до вызова.
    /// Вызывается, когда начинается работа с сервером; повторный вызов ничего не делает.
    func resumeDeliveries()
}

@MainActor
protocol MessageSendQueueProtocol: AuthServiceObserver, SessionDataLoading, UnsentMessagePreviewProviding,
    MessageDeliveryResuming, Sendable {
    /// Сообщения текущего пользователя во всех переписках, ещё не подтверждённые сервером, сначала самые старые.
    var outgoingMessages: [OutgoingMessage] { get }

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
/// в `sentMessages()`, убирает сообщение из очереди и записывается в кэш сообщений (`MessageCacheService.applySent`;
/// неотправленная копия удаляется из БД в той же записи). Событие WebSocket или страница переписки
/// с тем же `clientId` тоже подтверждают доставку. При ошибке сообщение и все ждущие отправки после него переходят
/// в статус «не отправлено» — так порядок не нарушится; каждое можно отправить повторно с тем же `clientId` или
/// удалить. Сообщение, `clientId` которого сервер отклонил как занятый (6004), удаляется сразу, а очередь идёт дальше.
///
/// Очередь пользователя загружается из БД при открытии сессии (`load(userId:)`, его вызывает `SessionService`),
/// но отправка начинается только с `resumeDeliveries()` — когда список чатов готов принять ответы. Отправки,
/// прерванные закрытием приложения, повторяются с тем же `clientId` — сервер не создаст дубль.
///
/// Очередь переживает выход из аккаунта: при выходе (`authServiceWillLogout`) текущий запрос отменяется,
/// отправляющиеся и ждущие сообщения становятся неотправленными, и выход дожидается всех записей в БД. Сообщения
/// пользователей разделяет ключ `(senderId, clientId)`; сообщения старше `unsentMessageLifetime` удаляются при
/// загрузке — у всех пользователей устройства. Для списка чатов очередь держит индекс `lastFailedTexts`.
@MainActor
@Observable
final class MessageSendQueue: MessageSendQueueProtocol {
    /// Чья очередь в памяти и что с ней можно делать.
    private enum State: Equatable {
        /// Сессии нет или очередь ещё не загружена: действия пользователя не принимаются.
        case idle
        /// Сессия пользователя открыта, он — отправитель новых сообщений. Если чтение БД не удалось, очередь
        /// начинает пустой, а неотправленные прошлых сессий появятся при следующей загрузке.
        case active(userId: Int)
        /// Идёт выход: новые сообщения, повторы и удаления не принимаются.
        case loggingOut
    }

    private(set) var outgoingMessages: [OutgoingMessage] = [] {
        didSet { updateLastFailedTexts() }
    }
    /// Текст последнего неотправленного сообщения каждой переписки — производный от `outgoingMessages`.
    /// Присваивается, только когда меняется: Observation сообщает о любом присваивании, и список чатов
    /// пересобирался бы на каждую смену статуса «отправляется».
    private(set) var lastFailedTexts: [Int: String] = [:]

    /// Сколько неотправленное сообщение живёт с момента отправки: более старые удаляются при загрузке — отправлять
    /// их уже поздно, а сообщения пользователей, которые больше не входят на устройстве, не копятся.
    static let unsentMessageLifetime: TimeInterval = 30 * 24 * 60 * 60

    private let messageService: MessageServiceProtocol
    private let messageCache: MessageCacheServiceProtocol
    private let outgoingMessageStorage: OutgoingMessageStorageServiceProtocol
    private let now: () -> Date
    private let makeClientId: () -> String

    @ObservationIgnored private var state = State.idle
    /// `true` после `resumeDeliveries()` в текущей сессии: до этого отправки только копятся в `pendingDeliveries`.
    @ObservationIgnored private var isDeliveryResumed = false
    /// `clientId` сообщений, ждущих отправки, в порядке очереди.
    @ObservationIgnored private var pendingDeliveries: [String] = []
    /// Задача, отправляющая сообщения по одному; `nil` — отправлять нечего.
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Последняя запись в БД: следующая начинается только после неё.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    /// Последняя загрузка: следующая начинается только после неё.
    @ObservationIgnored private var pendingLoad: Task<Void, Never>?
    /// Поколение очереди: выход из аккаунта его меняет, и результаты, полученные раньше, не применяются.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<Message>.Continuation] = [:]
    private let positionUpdater: ConversationPositionUpdating
    /// Подписка на очередь событий WebSocket — подтверждения собственных сообщений. Берётся в `init`: очередь
    /// создаётся раньше соединения, и события не пройдут мимо.
    @ObservationIgnored private var eventSubscription: RealtimeSubscription?

    /// - Parameters:
    ///   - messageService: отправка `/messages/send`.
    ///   - messageCache: кэш сообщений — куда записываются отправленные сообщения.
    ///   - outgoingMessageStorage: хранилище очереди в БД.
    ///   - eventQueue: очередь событий WebSocket — подтверждения собственных сообщений.
    ///   - positionUpdater: список чатов — поднимает переписку по ответу на отправку.
    ///   - now: текущее время; подменяется в тестах.
    ///   - makeClientId: генератор `clientId` новых сообщений (UUID v4); подменяется в тестах.
    init(
        messageService: MessageServiceProtocol,
        messageCache: MessageCacheServiceProtocol,
        outgoingMessageStorage: OutgoingMessageStorageServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        positionUpdater: ConversationPositionUpdating,
        now: @escaping () -> Date = { Date() },
        makeClientId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.messageService = messageService
        self.messageCache = messageCache
        self.outgoingMessageStorage = outgoingMessageStorage
        self.now = now
        self.makeClientId = makeClientId
        self.positionUpdater = positionUpdater
        eventSubscription = eventQueue.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    /// Текст последнего неотправленного сообщения переписки из памяти.
    /// - Parameter conversationId: переписка.
    func lastFailedText(for conversationId: Int) -> String? {
        lastFailedTexts[conversationId]
    }

    // MARK: - Загрузка

    /// Загружает очередь пользователя: дожидается предыдущей загрузки, иначе загрузки при старте и при входе могли бы
    /// применить результаты в обратном порядке. Не отправляет — см. `resumeDeliveries()`.
    /// - Parameter userId: пользователь открытой сессии.
    func load(userId: Int) async {
        let previous = pendingLoad
        let loading = Task { [weak self] in
            await previous?.value
            await self?.performLoad(userId: userId)
        }
        pendingLoad = loading
        await loading.value
    }

    /// Удаляет просроченные сообщения, читает очередь пользователя из БД и делает его отправителем. Сообщения
    /// в статусе «отправляется» встают в очередь отправки. Если очередь этого пользователя уже загружена — ничего
    /// не делает (и после ошибки чтения: повторной загрузки без выхода не бывает); если загружена очередь другого —
    /// сначала отбрасывает её (`abandonForeignSession()`). Ошибка чтения логируется, очередь остаётся пустой.
    ///
    /// Предусловие: загрузка применяется из `.idle`, где память пуста, — поэтому прочитанное заменяет память,
    /// а не сливается с ней.
    ///
    /// `.active` того же пользователя при загрузке бывает и тогда, когда его сессию завершили в обход `AuthService`
    /// (`SessionService.end()` / `expire()` напрямую — так быть не должно), а затем он вошёл снова. Перечитывать
    /// очередь и тогда не нужно: память совпадает с БД — все записи в БД идут через очередь, — отправка уже
    /// возобновлена, а сообщения, чья отправка за время без сессии не удалась, честно стали неотправленными.
    /// Этот путь не поддерживается как сценарий, но и не портит очередь.
    /// - Parameter userId: пользователь открытой сессии.
    private func performLoad(userId: Int) async {
        guard state != .active(userId: userId) else { return }
        if case .active = state {
            await abandonForeignSession()
        }
        let loadGeneration = generation
        await waitForAllWrites()
        await deleteExpiredMessages()
        let stored: [OutgoingMessage]
        do {
            stored = try await outgoingMessageStorage.fetchAll(senderId: userId)
        } catch {
            Logger.storage.error("Не удалось прочитать очередь отправки из БД: \(String(describing: error), privacy: .public)")
            stored = []
        }
        guard loadGeneration == generation else { return }
        state = .active(userId: userId)
        outgoingMessages = stored
        pendingDeliveries = stored.filter { $0.status == .sending }.map(\.clientId)
    }

    /// Отбрасывает очередь прежнего пользователя, чью сессию завершили в обход выхода. Так быть не должно: сессия
    /// завершается только через `AuthService`. Отправка отменяется, память очищается без записи в БД — сообщения
    /// прежнего пользователя остаются в БД в своём статусе и вернутся ему при следующем входе.
    private func abandonForeignSession() async {
        Logger.auth.fault("Очередь отправки: сессия сменилась без выхода из аккаунта")
        state = .idle
        isDeliveryResumed = false
        pendingDeliveries.removeAll()
        generation += 1
        let worker = worker
        worker?.cancel()
        await worker?.value
        outgoingMessages = []
    }

    /// Удаляет сообщения всех пользователей старше `unsentMessageLifetime`. Ошибка логируется и загрузку не
    /// останавливает.
    private func deleteExpiredMessages() async {
        do {
            try await outgoingMessageStorage.deleteAll(createdBefore: now().addingTimeInterval(-Self.unsentMessageLifetime))
        } catch {
            Logger.storage.error("Не удалось удалить просроченные сообщения очереди: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Действия

    /// Запускает отправку: загруженные сообщения в статусе «отправляется» и поставленные с тех пор уходят по порядку.
    /// Без загруженной очереди, во время выхода и при повторном вызове ничего не делает.
    func resumeDeliveries() {
        guard case .active = state, !isDeliveryResumed else { return }
        isDeliveryResumed = true
        startWorkerIfNeeded()
    }

    /// Создаёт сообщение пользователя загруженной очереди в статусе «отправляется», сохраняет его в БД и ставит
    /// в очередь. Без загруженной очереди и во время выхода ничего не делает.
    /// - Parameters:
    ///   - text: введённый текст; краевые пробелы и невидимые символы обрезаются, как это сделает сервер.
    ///   - conversationId: переписка, в которую уходит сообщение.
    func enqueue(text: String, conversationId: Int) {
        guard case let .active(senderId) = state else { return }
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
    /// сервер вернёт уже созданное сообщение. Без загруженной очереди и во время выхода ничего не делает.
    /// - Parameter clientId: идентификатор сообщения.
    func retry(clientId: String) {
        guard case .active = state,
              let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }),
              outgoingMessages[index].status == .failed else { return }
        outgoingMessages[index].status = .sending
        store(outgoingMessages[index])
        scheduleDelivery(clientId: clientId)
    }

    /// Удаляет неотправленное сообщение из очереди и БД. Без загруженной очереди и во время выхода ничего не делает.
    /// - Parameter clientId: идентификатор сообщения.
    func delete(clientId: String) {
        guard case .active = state,
              let index = outgoingMessages.firstIndex(where: { $0.clientId == clientId }),
              outgoingMessages[index].status == .failed else { return }
        let message = outgoingMessages.remove(at: index)
        removeStored(message)
    }

    /// Убирает из очереди сообщения, которые сервер уже создал: совпадают отправитель и `clientId`. Из БД их
    /// неотправленные копии удаляет `MessageCacheService` при записи серверных сообщений.
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

    /// Выход из аккаунта начинается (`AuthServiceObserver`): действия пользователя больше не принимаются, текущий
    /// запрос отменяется, отправляющиеся и ждущие сообщения становятся неотправленными. Выход дожидается всех
    /// записей в БД — очередь при выходе не очищается — и только потом очищает память.
    func authServiceWillLogout() async {
        state = .loggingOut
        isDeliveryResumed = false
        pendingDeliveries.removeAll()
        let worker = worker
        worker?.cancel()
        await worker?.value
        markFailed(clientIds: outgoingMessages.filter { $0.status == .sending }.map(\.clientId))
        await waitForAllWrites()
        generation += 1
        outgoingMessages = []
        state = .idle
    }

    // MARK: - Отправка

    /// Ставит отправку в конец очереди и запускает обработку, если отправка возобновлена и обработка не идёт.
    /// - Parameter clientId: идентификатор сообщения.
    private func scheduleDelivery(clientId: String) {
        pendingDeliveries.append(clientId)
        startWorkerIfNeeded()
    }

    /// Запускает обработку очереди отправки, если отправка возобновлена, обработка не идёт и есть что отправлять.
    private func startWorkerIfNeeded() {
        guard isDeliveryResumed, worker == nil, !pendingDeliveries.isEmpty else { return }
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
            let response = try await messageService.send(conversationId: message.conversationId, text: message.text, clientId: clientId)
            guard !Task.isCancelled else { return }
            confirm(response.message, readInfo: response.readInfo)
        } catch {
            guard !Task.isCancelled else { return }
            handleFailure(clientId: clientId, error: error)
        }
    }

    /// Применяет ответ сервера: поднимает переписку в списке чатов, публикует сообщение подписчикам, убирает его
    /// из очереди и ставит запись в БД. Запись не ждётся — следующее сообщение отправляется сразу. Неотправленную
    /// копию удаляет из БД кэш в той же записи; если кэш запись отбросил (он уже в выходе), копию удаляет очередь —
    /// иначе её не удалил бы никто. При ошибке записи копия остаётся в статусе «отправляется»: при следующей загрузке
    /// очередь отправит её повторно с тем же `clientId`, и серверное сообщение попадёт в кэш.
    /// - Parameters:
    ///   - message: созданное сервером сообщение.
    ///   - readInfo: прочтение переписки для отправителя из того же ответа.
    private func confirm(_ message: Message, readInfo: ReadInfo?) {
        positionUpdater.applySentMessage(message, readInfo: readInfo)
        subscribers.values.forEach { $0.yield(message) }
        removeConfirmed(by: [message])
        write("сохранить отправленное сообщение") { [messageCache, outgoingMessageStorage] in
            guard await messageCache.applySent(message) == .discarded else { return }
            try await outgoingMessageStorage.delete(senderId: message.senderId, clientId: message.clientId)
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
            let message = outgoingMessages.remove(at: index)
            removeStored(message)
            return
        }
        let failedIds = [clientId] + pendingDeliveries
        pendingDeliveries.removeAll()
        markFailed(clientIds: failedIds)
    }

    /// Переводит отправляющиеся сообщения в статус «не отправлено» и сохраняет статус в БД. Очередь меняется одним
    /// присваиванием — индекс `lastFailedTexts` пересчитывается один раз, — а в БД статусы пишутся одной записью.
    /// - Parameter clientIds: идентификаторы сообщений; удалённые и уже неотправленные пропускаются.
    private func markFailed(clientIds: [String]) {
        let ids = Set(clientIds)
        var messages = outgoingMessages
        var failed: [OutgoingMessage] = []
        for index in messages.indices where ids.contains(messages[index].clientId) && messages[index].status == .sending {
            messages[index].status = .failed
            failed.append(messages[index])
        }
        guard !failed.isEmpty else { return }
        outgoingMessages = messages
        store(failed)
    }

    /// Применяет событие WebSocket: собственное сообщение с тем же `clientId` подтверждает доставку.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) {
        switch event {
        case let .messageReceived(message, _, _), let .messageEdited(message, _, _):
            removeConfirmed(by: [message])
        case .connected, .conversationCreated, .conversationRead:
            break
        }
    }

    /// Пересчитывает `lastFailedTexts` из очереди: для каждой переписки — текст последнего неотправленного сообщения
    /// (очередь отсортирована по `createdAt`). Присваивает, только если результат изменился.
    private func updateLastFailedTexts() {
        var texts: [Int: String] = [:]
        for message in outgoingMessages where message.status == .failed {
            texts[message.conversationId] = message.text
        }
        guard texts != lastFailedTexts else { return }
        lastFailedTexts = texts
    }

    // MARK: - Локальная БД

    /// Сохраняет сообщение очереди в БД.
    /// - Parameter message: сообщение с актуальным статусом.
    private func store(_ message: OutgoingMessage) {
        store([message])
    }

    /// Сохраняет сообщения очереди в БД одной записью.
    /// - Parameter messages: сообщения с актуальным статусом.
    private func store(_ messages: [OutgoingMessage]) {
        write("сохранить сообщения очереди") { [outgoingMessageStorage] in
            try await outgoingMessageStorage.save(messages: messages)
        }
    }

    /// Удаляет сообщение очереди из БД.
    /// - Parameter message: удаляемое сообщение.
    private func removeStored(_ message: OutgoingMessage) {
        write("удалить сообщение очереди") { [outgoingMessageStorage] in
            try await outgoingMessageStorage.delete(senderId: message.senderId, clientId: message.clientId)
        }
    }

    /// Дожидается всей цепочки записей, включая записи, поставленные за время ожидания.
    private func waitForAllWrites() async {
        var awaited: Task<Void, Never>?
        while let current = lastWrite, current != awaited {
            await current.value
            awaited = current
        }
    }

    /// Ставит запись в БД в конец цепочки. Запись, поставленная до смены поколения, не выполняется — это защита
    /// от гонок: выход дожидается записей до смены поколения, и таких записей быть не должно.
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
