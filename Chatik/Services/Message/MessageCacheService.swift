//
//  MessageCacheService.swift
//  Chatik
//

import Foundation
import os

protocol MessageCacheServiceProtocol: Sendable {
    /// Синхронизирована ли переписка в текущем соединении.
    func isSynced(conversationId: Int) async -> Bool
    /// Состояние кэша переписки; `nil` — кэша нет.
    func cacheState(conversationId: Int) async throws -> MessageCacheState?
    /// Изменения кэша переписки — публикуются после записи в БД. Подписка регистрируется до возврата,
    /// поэтому подписываться нужно до чтения окна.
    func changes(conversationId: Int) async -> AsyncStream<MessageCacheChange>
    /// Начало синхронизации: запоминает соединение, начинает копить id из `applySent` и пропущенные события.
    func beginSync(conversationId: Int) async -> MessageSyncToken
    /// Записывает итог синхронизации одной транзакцией и, если условия выполнены, ставит признак.
    func applySync(_ result: MessageSyncResult, token: MessageSyncToken) async throws
    /// Конец синхронизации при любом исходе: освобождает защищённые id и счётчик пропущенных событий. Идемпотентен.
    func endSync(_ token: MessageSyncToken) async
    /// Дописывает более старую страницу, если продолжение подгрузки в кэше всё ещё `requestedBlockId`.
    /// - Returns: `false` — кэш за время запроса изменился (сброс), и страница не записана.
    func appendOlderPage(_ page: MessagesPage, requestedBlockId: Int, conversationId: Int) async throws -> Bool
    /// Сообщение из ответа `/messages/send`; его неотправленная копия удаляется в той же записи.
    /// - Returns: записано ли сообщение, отброшено выходом или запись не удалась.
    @discardableResult
    func applySent(_ message: Message) async -> SentMessageWriteResult
    /// Сообщение из ответа `/messages/edit`: обновляет его, если оно есть в БД, и публикует `.upserted`.
    /// Записей не создаёт. `syncMark` двигается только при признаке. Ошибка записи логируется.
    func applyEdited(_ message: Message) async
}

/// Итог записи сообщения из ответа `/messages/send` в кэш — по нему очередь отправки решает, удалять ли
/// неотправленную копию самой.
enum SentMessageWriteResult: Sendable {
    /// Сообщение записано, неотправленная копия удалена в той же транзакции.
    case written
    /// Кэш в выходе: запись отброшена, и копию, кроме очереди, никто не удалит.
    case discarded
    /// Запись не удалась: копия осталась в БД в статусе «отправляется» и при следующей загрузке очереди уйдёт
    /// повторно с тем же `clientId` — сервер вернёт уже созданное сообщение, и кэш запишет его.
    case failed
}

/// Выход из аккаунта для кэша сообщений — его передаёт `MessageCacheLogoutObserver`.
protocol MessageCacheLogoutHandling: Sendable {
    /// Начало выхода: кэш перестаёт принимать записи и дожидается начатых.
    func prepareForLogout() async
    /// Выход завершён: кэш снова принимает записи.
    func finishLogout() async
}

/// Идущая синхронизация одной переписки. Синхронизаций одной переписки может быть несколько одновременно
/// (второй экран той же переписки) — у каждой свой токен и свои защищённые id.
struct MessageSyncToken: Hashable, Sendable {
    let id: UInt64
    let conversationId: Int
    /// Соединение на момент `beginSync`; `nil` — соединения не было, признак не поставится.
    let connection: RealtimeConnectionId?
}

/// Итог синхронизации, который `MessagesListService` передаёт на запись.
enum MessageSyncResult: Sendable {
    /// Дельта: новые сообщения и полные блоки из `getBlockBatch`, кэш остаётся.
    case merge(messages: [Message], blocks: [MessageBlock])
    /// Сброс: первая страница без фильтра заменяет кэш.
    case reset(firstPage: MessagesPage)

    /// Все сообщения итога — для подтверждения доставки.
    var messages: [Message] {
        switch self {
        case let .merge(messages, blocks): return messages + blocks.flatMap(\.messages)
        case let .reset(page): return page.messages
        }
    }
}

/// Изменение кэша переписки после записи в БД.
enum MessageCacheChange: Sendable {
    /// Сообщения записаны (`received`, `edited`, `applySent`) — версии после слияния, как в БД.
    case upserted([Message])
    /// Кэш перезаписан синхронизацией — окно нужно перечитать.
    case rewritten(by: MessageSyncToken)
}

/// Единственный писатель сообщений в БД: события WebSocket, ответы `/messages/send`, результаты синхронизации
/// и подгрузки. Он же единственный решает, синхронизирована ли переписка, и публикует изменения кэша после записи.
///
/// **Признак «синхронизирована»** — id соединения, в котором прошла синхронизация, только в памяти. Переписка
/// синхронизирована, пока этот id совпадает с текущим соединением (`RealtimeConnectionMonitor`): с разрывом все
/// признаки разом гаснут, на старте приложения их нет. Признак ставит `applySync`, если соединение не сменилось
/// с `beginSync` и за это время не было проигнорировано ни одно событие переписки.
///
/// **События.** В синхронизированную переписку событие записывается; в несинхронизированную — нет (следующая
/// синхронизация вернёт его: `syncMark` без признака не двигается), удаляется только неотправленная копия.
/// `edited` по сообщению, которого нет в БД, его не создаёт — запись создала бы дыру в непрерывном кэше.
///
/// **Порядок.** Все записи идут одной последовательной цепочкой в порядке событий и вызовов. Обработчик события
/// не ждёт CoreData — он ставит запись в цепочку, и события подряд склеиваются в одну транзакцию. Изменения
/// публикуются в `changes` после коммита, поэтому лента видит только то, что уже есть в БД.
///
/// Подробности — `docs/messages-sync-architecture.md`.
actor MessageCacheService: MessageCacheServiceProtocol, MessageCacheLogoutHandling {
    /// Идущая синхронизация.
    private struct SyncState {
        let token: MessageSyncToken
        /// Проигнорировано событие переписки: признак ставить нельзя.
        var missedEvents = false
        /// Сообщения, записанные после `beginSync`, — их не удаляют сброс и замена блоков.
        var protectedIds: Set<Int> = []
    }

    private let storage: MessageStorageReading & MessageStorageWriting
    private let connectionMonitor: RealtimeConnectionMonitoring

    /// Признаки: переписка → соединение, в котором она синхронизирована.
    private var syncedIn: [Int: RealtimeConnectionId] = [:]
    private var syncs: [UInt64: SyncState] = [:]
    private var lastTokenId: UInt64 = 0
    private var subscribers: [Int: [UUID: AsyncStream<MessageCacheChange>.Continuation]] = [:]
    /// Последняя запись цепочки: следующая начинается только после неё.
    private var lastWrite: Task<Void, Never>?
    /// Записи событий, ещё не начатые, по id пачки; открытая пачка принимает новые события.
    private var eventBatches: [Int: MessageStorageChanges] = [:]
    private var openBatchId: Int?
    private var lastBatchId = 0
    /// Поколение: выход из аккаунта его меняет, и записи, поставленные раньше, не выполняются.
    private var generation = 0
    /// `true` между `authServiceWillLogout` и `authServiceDidLogout`: новые записи не принимаются.
    private var isLoggingOut = false

    /// - Parameters:
    ///   - storage: хранилище сообщений и состояния кэша.
    ///   - connectionMonitor: текущее WebSocket-соединение.
    init(storage: MessageStorageReading & MessageStorageWriting, connectionMonitor: RealtimeConnectionMonitoring) {
        self.storage = storage
        self.connectionMonitor = connectionMonitor
    }

    /// Подписывает кэш на очередь событий. Подписка должна появиться до запуска соединения: очередь не хранит
    /// события для будущих подписчиков.
    /// - Parameters:
    ///   - cache: кэш сообщений.
    ///   - queue: очередь событий WebSocket.
    /// - Returns: токен подписки — подписка живёт, пока он жив.
    @MainActor
    static func subscribe(_ cache: MessageCacheService, to queue: RealtimeEventQueueProtocol) -> RealtimeSubscription {
        queue.subscribe { [weak cache] event in
            await cache?.handle(event)
        }
    }

    // MARK: - Состояние

    /// Синхронизирована ли переписка в текущем соединении.
    /// - Parameter conversationId: переписка.
    func isSynced(conversationId: Int) -> Bool {
        guard let connection = syncedIn[conversationId] else { return false }
        return connection == connectionMonitor.current
    }

    /// Состояние кэша переписки.
    /// - Parameter conversationId: переписка.
    func cacheState(conversationId: Int) async throws -> MessageCacheState? {
        try await storage.fetchState(conversationId: conversationId)
    }

    /// Подписывает на изменения кэша переписки; подписка регистрируется до возврата.
    /// - Parameter conversationId: переписка.
    func changes(conversationId: Int) -> AsyncStream<MessageCacheChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: MessageCacheChange.self)
        let id = UUID()
        subscribers[conversationId, default: [:]][id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id, conversationId: conversationId) }
        }
        return stream
    }

    /// Отписывает подписчика на изменения.
    /// - Parameters:
    ///   - id: подписчик.
    ///   - conversationId: переписка.
    private func removeSubscriber(_ id: UUID, conversationId: Int) {
        subscribers[conversationId]?[id] = nil
    }

    /// Публикует изменение подписчикам переписки.
    /// - Parameters:
    ///   - change: изменение.
    ///   - conversationId: переписка.
    private func publish(_ change: MessageCacheChange, conversationId: Int) {
        subscribers[conversationId]?.values.forEach { $0.yield(change) }
    }

    /// Публикует записанные сообщения подписчикам их переписок.
    /// - Parameter messages: версии сообщений из БД.
    private func publishUpserted(_ messages: [Message]) {
        for (conversationId, messages) in Dictionary(grouping: messages, by: \.conversationId) {
            publish(.upserted(messages), conversationId: conversationId)
        }
    }

    // MARK: - События WebSocket

    /// Применяет событие очереди: ставит запись в цепочку, не дожидаясь её.
    /// - Parameter event: событие реального времени.
    func handle(_ event: RealtimeEvent) {
        guard !isLoggingOut else { return }
        switch event {
        case let .messageReceived(message, _, _):
            handleMessageEvent(message, isNew: true)
        case let .messageEdited(message, _, _):
            handleMessageEvent(message, isNew: false)
        case .connected, .conversationCreated, .conversationRead, .memberRead, .group:
            break
        }
    }

    /// Ставит в пачку записей событие о сообщении. В синхронизированную переписку сообщение пишется и двигает
    /// `syncMark`; в несинхронизированную — только удаляется его неотправленная копия, а идущие синхронизации
    /// переписки узнают, что событие пропущено.
    /// - Parameters:
    ///   - message: сообщение события.
    ///   - isNew: `received` — upsert; `edited` — обновить, только если сообщение есть в БД.
    private func handleMessageEvent(_ message: Message, isNew: Bool) {
        let conversationId = message.conversationId
        let isSynced = isSynced(conversationId: conversationId)
        appendToEventBatch { changes in
            changes.confirmed.append(message)
            guard isSynced else { return }
            if isNew {
                changes.upserts.append(message)
            } else {
                changes.updatesOfExisting.append(message)
            }
            let mark = max(message.createdAt, message.updatedAt)
            changes.stateChanges.append(MessageCacheStateChange(conversationId: conversationId, kind: .advanceSyncMark(mark)))
        }
        if !isSynced {
            updateSyncs(of: conversationId) { $0.missedEvents = true }
        } else if isNew {
            updateSyncs(of: conversationId) { $0.protectedIds.insert(message.messageId) }
        }
    }

    /// Добавляет изменения в открытую пачку записей событий; если её нет — открывает новую и ставит её запись
    /// в конец цепочки. Пачка принимает события, пока в цепочку не встанет другая запись.
    /// - Parameter update: изменения пачки.
    private func appendToEventBatch(_ update: (inout MessageStorageChanges) -> Void) {
        let batchId: Int
        if let openBatchId {
            batchId = openBatchId
        } else {
            lastBatchId += 1
            batchId = lastBatchId
            enqueueWrite { try await self.writeEventBatch(batchId) }
            openBatchId = batchId
        }
        update(&eventBatches[batchId, default: MessageStorageChanges()])
    }

    /// Записывает пачку событий и публикует записанные сообщения. Ошибка записи логируется: событие не потеряно
    /// навсегда — синхронизация при следующем открытии вернёт его.
    /// - Parameter batchId: пачка.
    private func writeEventBatch(_ batchId: Int) async throws {
        if openBatchId == batchId {
            openBatchId = nil
        }
        guard let changes = eventBatches.removeValue(forKey: batchId) else { return }
        do {
            publishUpserted(try await storage.write(changes))
        } catch {
            Logger.storage.error("Не удалось сохранить события WebSocket в БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Меняет состояние всех идущих синхронизаций переписки.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - update: изменение.
    private func updateSyncs(of conversationId: Int, _ update: (inout SyncState) -> Void) {
        for id in syncs.keys where syncs[id]?.token.conversationId == conversationId {
            update(&syncs[id]!)
        }
    }

    // MARK: - Отправка

    /// Записывает сообщение из ответа `/messages/send` — всегда, и в несинхронизированную переписку: экран уже
    /// показывает его, и после перечитывания окна оно не должно пропасть. `syncMark` двигается только при признаке.
    /// Неотправленная копия удаляется в той же транзакции. Ошибка записи логируется.
    /// - Parameter message: созданное сервером сообщение.
    /// - Returns: `.written`; `.discarded` — идёт выход (запись отброшена или отменена), неотправленную копию тогда
    ///   удаляет очередь отправки; `.failed` — ошибка записи, копия остаётся для повторной отправки.
    @discardableResult
    func applySent(_ message: Message) async -> SentMessageWriteResult {
        guard !isLoggingOut else { return .discarded }
        let conversationId = message.conversationId
        var changes = MessageStorageChanges(upserts: [message], confirmed: [message])
        if isSynced(conversationId: conversationId) {
            let mark = max(message.createdAt, message.updatedAt)
            changes.stateChanges = [MessageCacheStateChange(conversationId: conversationId, kind: .advanceSyncMark(mark))]
        }
        updateSyncs(of: conversationId) { $0.protectedIds.insert(message.messageId) }
        let task = enqueueWrite { [changes] in self.publishUpserted(try await self.storage.write(changes)) }
        do {
            try await task.value
            return .written
        } catch is CancellationError {
            return .discarded
        } catch {
            Logger.storage.error("Не удалось сохранить отправленное сообщение: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    // MARK: - Редактирование

    /// Записывает сообщение из ответа `/messages/edit`, если оно есть в БД, — и в несинхронизированную переписку:
    /// экран уже показывает это сообщение, и новый текст должен появиться без ожидания события и синхронизации.
    /// Записей не создаёт, иначе в непрерывном кэше появилась бы дыра. `syncMark` двигается только при признаке.
    /// Идущие синхронизации переписки не удаляют сообщение (`protectedIds`), а их более старая версия не затрёт
    /// новую: при записи побеждает больший `updatedAt`. Во время выхода запись отбрасывается.
    /// - Parameter message: отредактированное сообщение.
    func applyEdited(_ message: Message) async {
        guard !isLoggingOut else { return }
        let conversationId = message.conversationId
        var changes = MessageStorageChanges(updatesOfExisting: [message])
        if isSynced(conversationId: conversationId) {
            let mark = max(message.createdAt, message.updatedAt)
            changes.stateChanges = [MessageCacheStateChange(conversationId: conversationId, kind: .advanceSyncMark(mark))]
        }
        updateSyncs(of: conversationId) { $0.protectedIds.insert(message.messageId) }
        let task = enqueueWrite { [changes] in self.publishUpserted(try await self.storage.write(changes)) }
        do {
            try await task.value
        } catch is CancellationError {
            return
        } catch {
            Logger.storage.error("Не удалось сохранить отредактированное сообщение: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Синхронизация

    /// Начинает синхронизацию переписки.
    /// - Parameter conversationId: переписка.
    func beginSync(conversationId: Int) -> MessageSyncToken {
        lastTokenId += 1
        let token = MessageSyncToken(id: lastTokenId, conversationId: conversationId, connection: connectionMonitor.current)
        syncs[token.id] = SyncState(token: token)
        return token
    }

    /// Заканчивает синхронизацию.
    /// - Parameter token: синхронизация.
    func endSync(_ token: MessageSyncToken) {
        syncs[token.id] = nil
    }

    /// Записывает итог синхронизации одной транзакцией и публикует `.rewritten`.
    /// - Parameters:
    ///   - result: дельта или сброс.
    ///   - token: синхронизация; закрытая `endSync` — `CancellationError`, ничего не пишется.
    func applySync(_ result: MessageSyncResult, token: MessageSyncToken) async throws {
        guard !isLoggingOut, syncs[token.id] != nil else { throw CancellationError() }
        try await enqueueWrite { try await self.writeSync(result, token: token) }.value
    }

    /// Запись итога синхронизации в цепочке. Признак ставится после коммита, в том же шаге актора — атомарно
    /// с проверкой пропущенных событий.
    /// - Parameters:
    ///   - result: дельта или сброс.
    ///   - token: синхронизация.
    private func writeSync(_ result: MessageSyncResult, token: MessageSyncToken) async throws {
        guard let sync = syncs[token.id] else { throw CancellationError() }
        let changes = Self.makeChanges(for: result, conversationId: token.conversationId, protectedIds: sync.protectedIds)
        _ = try await storage.write(changes)
        if canMarkSynced(token) {
            syncedIn[token.conversationId] = token.connection
        }
        publish(.rewritten(by: token), conversationId: token.conversationId)
    }

    /// Можно ли поставить признак: соединение с `beginSync` не сменилось и ни одно событие переписки
    /// не проигнорировано. Проверка заменяет `lease.isExpired`: истёкшая аренда даёт пропущенное событие.
    /// - Parameter token: синхронизация.
    private func canMarkSynced(_ token: MessageSyncToken) -> Bool {
        guard let sync = syncs[token.id], let connection = token.connection else { return false }
        return connection == connectionMonitor.current && !sync.missedEvents
    }

    /// Изменения БД для итога синхронизации. `syncMark` двигается и без признака — ответ отражает состояние
    /// сервера на момент запроса (отступление от серверного документа, см. архитектуру).
    /// - Parameters:
    ///   - result: дельта или сброс.
    ///   - conversationId: переписка.
    ///   - protectedIds: сообщения, записанные после начала синхронизации, — их не удалять.
    static func makeChanges(for result: MessageSyncResult, conversationId: Int, protectedIds: Set<Int>) -> MessageStorageChanges {
        var changes = MessageStorageChanges(protectedMessageIds: protectedIds, confirmed: result.messages)
        switch result {
        case let .merge(messages, blocks):
            let ownBlocks = blocks.filter { $0.conversationId == conversationId }
            changes.upserts = messages
            changes.replacedBlocks = ownBlocks
            if let mark = syncMark(messages: messages + ownBlocks.flatMap(\.messages), blocks: ownBlocks) {
                changes.stateChanges = [MessageCacheStateChange(conversationId: conversationId, kind: .advanceSyncMark(mark))]
            }
        case let .reset(page):
            changes.upserts = page.messages
            changes.replacedConversationId = conversationId
            let state = MessageCacheState(
                syncMark: syncMark(messages: page.messages, blocks: []) ?? ServerTime(milliseconds: 0),
                nextBlockId: page.hasNext ? page.nextBlockId : nil,
                hasMorePages: page.hasNext && page.nextBlockId != nil
            )
            changes.stateChanges = [MessageCacheStateChange(conversationId: conversationId, kind: .replace(state))]
        }
        return changes
    }

    /// Отметка по полученным данным: максимум `createdAt` / `updatedAt` сообщений и `updatedAt` блоков.
    /// - Parameters:
    ///   - messages: сообщения.
    ///   - blocks: блоки из `getBlockBatch`.
    /// - Returns: `nil` — данных нет.
    static func syncMark(messages: [Message], blocks: [MessageBlock]) -> ServerTime? {
        let times = messages.flatMap { [$0.createdAt, $0.updatedAt] } + blocks.compactMap(\.updatedAt)
        return times.max()
    }

    // MARK: - Подгрузка

    /// Дописывает более старую страницу. Проверка продолжения и запись идут в цепочке, поэтому между ними
    /// никакая другая запись не вклинится.
    /// - Parameters:
    ///   - page: страница `getList` по `blockId`.
    ///   - requestedBlockId: `nextBlockId` кэша, с которым запрошена страница.
    ///   - conversationId: переписка.
    func appendOlderPage(_ page: MessagesPage, requestedBlockId: Int, conversationId: Int) async throws -> Bool {
        guard !isLoggingOut else { throw CancellationError() }
        return try await enqueueWrite { () async throws -> Bool in
            let state = try await self.storage.fetchState(conversationId: conversationId)
            guard state?.nextBlockId == requestedBlockId else { return false }
            let pagination = MessageCacheStateChange.Kind.setPagination(
                nextBlockId: page.hasNext ? page.nextBlockId : nil,
                hasMorePages: page.hasNext && page.nextBlockId != nil
            )
            let changes = MessageStorageChanges(
                upserts: page.messages,
                confirmed: page.messages,
                stateChanges: [MessageCacheStateChange(conversationId: conversationId, kind: pagination)]
            )
            _ = try await self.storage.write(changes)
            return true
        }.value
    }

    // MARK: - Цепочка записей

    /// Ставит запись в конец цепочки и закрывает открытую пачку событий: события после этой записи попадут
    /// в новую пачку — так порядок записей совпадает с порядком событий и вызовов. Запись, поставленная
    /// до выхода из аккаунта, не выполняется (`CancellationError`).
    /// - Parameter operation: запись; выполняется на акторе.
    /// - Returns: задача записи — чтобы дождаться результата.
    @discardableResult
    private func enqueueWrite<T: Sendable>(_ operation: @escaping () async throws -> T) -> Task<T, Error> {
        openBatchId = nil
        let previous = lastWrite
        let generation = generation
        let task = Task { () async throws -> T in
            await previous?.value
            guard generation == self.generation else { throw CancellationError() }
            return try await operation()
        }
        lastWrite = Task { _ = await task.result }
        return task
    }

    /// Дожидается записей, уже поставленных в цепочку.
    func waitForWrites() async {
        await lastWrite?.value
    }

    // MARK: - Удаление переписки

    /// Пользователь больше не участник переписки: признак, синхронизации и подписчики переписки сбрасываются,
    /// сообщения и состояние кэша удаляются — через цепочку записей, после записей, поставленных раньше: иначе пачка
    /// событий, поставленная до удаления, дописала бы сообщения после него.
    /// - Parameter conversationId: переписка.
    func removeConversation(_ conversationId: Int) async {
        guard !isLoggingOut else { return }
        syncedIn[conversationId] = nil
        syncs = syncs.filter { $0.value.token.conversationId != conversationId }
        subscribers[conversationId]?.values.forEach { $0.finish() }
        subscribers[conversationId] = nil
        var changes = MessageStorageChanges()
        changes.removedConversationId = conversationId
        _ = await enqueueWrite { [changes] in try await self.storage.write(changes) }.result
    }

    // MARK: - Выход из аккаунта

    /// Начало выхода: признаки, синхронизации и подписки сбрасываются, поставленные записи отменяются, начатые
    /// дожидаются — ничего не попадёт в БД после её очистки.
    func prepareForLogout() async {
        isLoggingOut = true
        generation += 1
        syncedIn = [:]
        syncs = [:]
        eventBatches = [:]
        openBatchId = nil
        subscribers.values.flatMap(\.values).forEach { $0.finish() }
        subscribers = [:]
        await lastWrite?.value
    }

    /// Выход завершён: кэш снова принимает записи.
    func finishLogout() {
        isLoggingOut = false
    }
}

/// Удаление переписки из кэша сообщений — всё, что о нём знает `MessageCacheRemovalObserver`.
protocol MessageCacheRemovalHandling: Sendable {
    /// Удаляет сообщения и состояние кэша переписки после уже поставленных записей.
    func removeConversation(_ conversationId: Int) async
}

extension MessageCacheService: MessageCacheRemovalHandling {}

/// Наблюдатель удаления переписки для `MessageCacheService`: актор не может реализовать протокол, изолированный
/// на main. `ConversationListService` держит наблюдателей слабо, поэтому адаптер хранит владелец (`DIContainer`).
@MainActor
final class MessageCacheRemovalObserver: ConversationRemovalObserver {
    private let messageCache: MessageCacheRemovalHandling

    /// - Parameter messageCache: кэш сообщений.
    init(messageCache: MessageCacheRemovalHandling) {
        self.messageCache = messageCache
    }

    /// Удаляет сообщения переписки, в которой пользователь больше не состоит.
    /// - Parameter info: удалённая переписка.
    func conversationWasRemoved(_ info: RemovedConversationInfo) async {
        await messageCache.removeConversation(info.conversationId)
    }
}

/// Наблюдатель выхода из аккаунта для `MessageCacheService`. `AuthServiceObserver` изолирован на main, а актор
/// не может реализовать протокол, изолированный на глобальном акторе, — выход передаётся через этот адаптер.
/// `AuthService` держит наблюдателей слабо, поэтому адаптер хранит владелец (`DIContainer`).
@MainActor
final class MessageCacheLogoutObserver: AuthServiceObserver {
    private let messageCache: MessageCacheLogoutHandling

    /// - Parameter messageCache: кэш сообщений.
    init(messageCache: MessageCacheLogoutHandling) {
        self.messageCache = messageCache
    }

    /// Выход начинается: кэш перестаёт принимать записи и дожидается начатых.
    func authServiceWillLogout() async {
        await messageCache.prepareForLogout()
    }

    /// Выход завершён: кэш снова принимает записи.
    /// - Parameter reason: причина выхода; на кэш не влияет.
    func authServiceDidLogout(reason: LogoutReason) async {
        await messageCache.finishLogout()
    }
}
