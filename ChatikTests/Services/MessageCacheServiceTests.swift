//
//  MessageCacheServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

@MainActor
final class MessageCacheServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var storage: MessageStorageService!
    private var monitor: RealtimeConnectionMonitor!
    private var sut: MessageCacheService!

    override func setUp() async throws {
        try await super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        storage = MessageStorageService(container: container)
        monitor = RealtimeConnectionMonitor()
        sut = MessageCacheService(storage: storage, connectionMonitor: monitor)
    }

    // MARK: - События

    /// Кейс: синхронизированная переписка получила `received`.
    /// Ожидание: сообщение записано, опубликовано `upserted` после записи, `syncMark` сдвинут до его времени.
    func test_received_synced_writesPublishesAndAdvancesMark() async throws {
        try await makeSynced(page: [.make(id: 1)])
        var changes = await sut.changes(conversationId: 1).makeAsyncIterator()
        let message = Message.make(id: 2, createdAt: .stub(5000))

        await sut.handle(.messageReceived(message, LastMessage(message: message)))

        let change = await changes.next()
        guard case let .upserted(published) = change else { return XCTFail("Ожидалось upserted, получено \(String(describing: change))") }
        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertEqual(published, [message])
        XCTAssertEqual(stored.map(\.id), [2, 1])
        XCTAssertEqual(state?.syncMark, .stub(5000))
    }

    /// Кейс: несинхронизированная переписка получила `received` своего сообщения, неотправленная копия которого
    /// лежит в очереди отправки.
    /// Ожидание: сообщение не записано, `syncMark` не сдвинут, но неотправленная копия удалена.
    func test_received_notSynced_onlyDeletesOutgoingCopy() async throws {
        try await writeState(conversationId: 1, syncMark: .stub)
        let outgoingStorage = OutgoingMessageStorageService(container: container)
        try await outgoingStorage.save(message: .stub(clientId: "c1", senderId: 1))
        let message = Message.make(id: 2, senderId: 1, clientId: "c1", createdAt: .stub(5000))

        await sut.handle(.messageReceived(message, LastMessage(message: message)))
        await sut.waitForWrites()

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        let state = try await storage.fetchState(conversationId: 1)
        let outgoing = try await outgoingStorage.fetchAll(senderId: 1)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(state?.syncMark, .stub)
        XCTAssertTrue(outgoing.isEmpty)
    }

    /// Кейс: синхронизированная переписка получила `edited` по сообщению, которого нет в БД.
    /// Ожидание: сообщение не создано — оно старше кэша, и запись создала бы дыру.
    func test_edited_missingMessage_isNotCreated() async throws {
        try await makeSynced(page: [.make(id: 5)])
        let edited = Message.make(id: 1, updatedAt: .stub(9000))

        await sut.handle(.messageEdited(edited, nil))
        await sut.waitForWrites()

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(stored.map(\.id), [5])
    }

    /// Кейс: пока идёт запись события, пришли ещё два события синхронизированной переписки.
    /// Ожидание: они записаны одной транзакцией после первой и опубликованы одним изменением.
    func test_eventsDuringWrite_areBatched() async throws {
        let gated = GatedMessageStorage(storage: storage)
        sut = MessageCacheService(storage: gated, connectionMonitor: monitor)
        try await makeSynced(page: [])
        var changes = await sut.changes(conversationId: 1).makeAsyncIterator()
        let gate = Gate()
        gated.gate = gate
        let messages = (1...3).map { Message.make(id: $0) }

        await sut.handle(.messageReceived(messages[0], LastMessage(message: messages[0])))
        await waitUntil { gate.isWaiting }
        gated.gate = nil
        await sut.handle(.messageReceived(messages[1], LastMessage(message: messages[1])))
        await sut.handle(.messageReceived(messages[2], LastMessage(message: messages[2])))
        gate.open()

        let first = await changes.next()
        let second = await changes.next()
        guard case let .upserted(firstBatch) = first, case let .upserted(secondBatch) = second else {
            return XCTFail("Ожидались два upserted")
        }
        XCTAssertEqual(firstBatch.map(\.id), [1])
        XCTAssertEqual(secondBatch.map(\.id), [2, 3])
        XCTAssertEqual(gated.writeCount, 3)
    }

    // MARK: - Признак

    /// Кейс: переписка синхронизирована, затем соединение сменилось.
    /// Ожидание: признак погас без отдельного сброса.
    func test_isSynced_connectionChanged_isFalse() async throws {
        try await makeSynced(page: [])
        let syncedBefore = await sut.isSynced(conversationId: 1)

        monitor.connect()

        let syncedAfter = await sut.isSynced(conversationId: 1)
        XCTAssertTrue(syncedBefore)
        XCTAssertFalse(syncedAfter)
    }

    /// Кейс: во время синхронизации соединение сменилось.
    /// Ожидание: итог записан (и `syncMark` сдвинут), но признак не поставлен.
    func test_applySync_connectionChangedDuringSync_doesNotMarkSynced() async throws {
        monitor.connect()
        let token = await sut.beginSync(conversationId: 1)
        monitor.connect()

        try await sut.applySync(.reset(firstPage: page([.make(id: 1, createdAt: .stub(3000))])), token: token)
        await sut.endSync(token)

        let isSynced = await sut.isSynced(conversationId: 1)
        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertFalse(isSynced)
        XCTAssertEqual(state?.syncMark, .stub(3000))
    }

    /// Кейс: синхронизации без соединения.
    /// Ожидание: признак не поставлен.
    func test_applySync_withoutConnection_doesNotMarkSynced() async throws {
        let token = await sut.beginSync(conversationId: 1)

        try await sut.applySync(.reset(firstPage: page([])), token: token)

        let isSynced = await sut.isSynced(conversationId: 1)
        XCTAssertFalse(isSynced)
    }

    /// Кейс: во время синхронизации событие переписки проигнорировано — например, аренда истекла, и очередь
    /// доставила его раньше записи итога.
    /// Ожидание: признак не поставлен — иначе пропущенное событие не вернулось бы до конца соединения.
    func test_applySync_eventMissedDuringSync_doesNotMarkSynced() async throws {
        monitor.connect()
        let token = await sut.beginSync(conversationId: 1)
        let missed = Message.make(id: 2)
        await sut.handle(.messageReceived(missed, LastMessage(message: missed)))

        try await sut.applySync(.reset(firstPage: page([.make(id: 1)])), token: token)

        let isSynced = await sut.isSynced(conversationId: 1)
        XCTAssertFalse(isSynced)
    }

    /// Кейс: событие пропущено во время синхронизации другой переписки.
    /// Ожидание: признак синхронизируемой переписки поставлен.
    func test_applySync_eventOfOtherConversation_marksSynced() async throws {
        monitor.connect()
        let token = await sut.beginSync(conversationId: 1)
        let other = Message.make(id: 9, conversationId: 2)
        await sut.handle(.messageReceived(other, LastMessage(message: other)))

        try await sut.applySync(.reset(firstPage: page([])), token: token)

        let isSynced = await sut.isSynced(conversationId: 1)
        XCTAssertTrue(isSynced)
    }

    /// Кейс: синхронизация закрыта `endSync` (ошибка или отмена), затем пришёл её итог.
    /// Ожидание: `applySync` бросает `CancellationError` и ничего не пишет.
    func test_applySync_afterEndSync_throwsAndWritesNothing() async throws {
        monitor.connect()
        let token = await sut.beginSync(conversationId: 1)
        await sut.endSync(token)

        do {
            try await sut.applySync(.reset(firstPage: page([.make(id: 1)])), token: token)
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertNil(state)
    }

    // MARK: - Отметка синхронизации

    /// Кейс: дельта с новым сообщением и блоком, изменённым позже всех сообщений.
    /// Ожидание: `syncMark` — максимум из времени сообщений и `updatedAt` блока.
    func test_applySync_merge_marksMaxOfMessagesAndBlocks() async throws {
        try await makeSynced(page: [.make(id: 1, blockId: 1)])
        let token = await sut.beginSync(conversationId: 1)
        let block = MessageBlock(blockId: 1, conversationId: 1, messages: [], updatedAt: .stub(9000))

        try await sut.applySync(.merge(messages: [.make(id: 2, createdAt: .stub(4000), blockId: 2)], blocks: [block]), token: token)

        let state = try await storage.fetchState(conversationId: 1)
        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(state?.syncMark, .stub(9000))
        XCTAssertEqual(stored.map(\.id), [2])
    }

    // MARK: - Отправка

    /// Кейс: ответ на отправку в несинхронизированную переписку, у которой нет записи о состоянии.
    /// Ожидание: сообщение записано (экран его показывает), состояние не создано, изменение опубликовано.
    func test_applySent_notSynced_writesWithoutState() async throws {
        var changes = await sut.changes(conversationId: 1).makeAsyncIterator()

        await sut.applySent(.make(id: 3))

        let change = await changes.next()
        guard case let .upserted(published) = change else { return XCTFail("Ожидалось upserted") }
        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertEqual(published.map(\.id), [3])
        XCTAssertEqual(stored.map(\.id), [3])
        XCTAssertNil(state)
    }

    /// Кейс: ответ на отправку, неотправленная копия которого лежит в очереди отправки.
    /// Ожидание: `applySent` вернул `.written`, сообщение записано, копия удалена в той же записи.
    func test_applySent_written_returnsWrittenAndDeletesCopy() async throws {
        let outgoingStorage = OutgoingMessageStorageService(container: container)
        try await outgoingStorage.save(message: .stub(clientId: "c1", senderId: 1))

        let result = await sut.applySent(.make(id: 3, senderId: 1, clientId: "c1"))

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        let outgoing = try await outgoingStorage.fetchAll(senderId: 1)
        XCTAssertEqual(result, .written)
        XCTAssertEqual(stored.map(\.id), [3])
        XCTAssertTrue(outgoing.isEmpty)
    }

    /// Кейс: ответ на отправку пришёл, когда кэш уже в выходе.
    /// Ожидание: `applySent` вернул `.discarded` — запись отброшена, неотправленную копию удалит очередь.
    func test_applySent_duringLogout_returnsDiscarded() async throws {
        await sut.prepareForLogout()

        let result = await sut.applySent(.make(id: 3))

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(result, .discarded)
        XCTAssertTrue(stored.isEmpty)
    }

    /// Кейс: ответ на отправку, запись в БД не удалась.
    /// Ожидание: `applySent` вернул `.failed` — копия остаётся для повторной отправки, очередь её не удаляет.
    func test_applySent_writeError_returnsFailed() async {
        let sut = MessageCacheService(storage: FailingMessageStorage(reading: storage), connectionMonitor: monitor)

        let result = await sut.applySent(.make(id: 3))

        XCTAssertEqual(result, .failed)
    }

    /// Кейс: ответ на отправку в несинхронизированную переписку с кэшем.
    /// Ожидание: `syncMark` не сдвинут — иначе пропущенные без соединения сообщения не вернулись бы.
    func test_applySent_notSynced_doesNotAdvanceMark() async throws {
        try await writeState(conversationId: 1, syncMark: .stub)

        await sut.applySent(.make(id: 3, createdAt: .stub(7000)))

        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertEqual(state?.syncMark, .stub)
    }

    /// Кейс: ответ на отправку в синхронизированную переписку.
    /// Ожидание: `syncMark` сдвинут.
    func test_applySent_synced_advancesMark() async throws {
        try await makeSynced(page: [])

        await sut.applySent(.make(id: 3, createdAt: .stub(7000)))

        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertEqual(state?.syncMark, .stub(7000))
    }

    // MARK: - Исключения из удаления

    /// Кейс: после начала синхронизации пришёл ответ на отправку; затем записан сброс, в странице которого
    /// этого сообщения нет.
    /// Ожидание: отправленное сообщение не удалено сбросом.
    func test_applySync_reset_keepsSentAfterBeginSync() async throws {
        try await writeState(conversationId: 1, syncMark: .stub)
        _ = try await storage.write(MessageStorageChanges(upserts: [.make(id: 1)]))
        let token = await sut.beginSync(conversationId: 1)
        await sut.applySent(.make(id: 7))

        try await sut.applySync(.reset(firstPage: page([.make(id: 5)])), token: token)

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(stored.map(\.id), [7, 5])
    }

    /// Кейс: после начала синхронизации пришёл ответ на отправку; блок применяется целиком без него.
    /// Ожидание: отправленное сообщение не удалено заменой блока.
    func test_applySync_replacedBlock_keepsSentAfterBeginSync() async throws {
        try await makeSynced(page: [.make(id: 1, blockId: 3)])
        let token = await sut.beginSync(conversationId: 1)
        await sut.applySent(.make(id: 2, blockId: 3))
        let block = MessageBlock(blockId: 3, conversationId: 1, messages: [.make(id: 1, blockId: 3)], updatedAt: nil)

        try await sut.applySync(.merge(messages: [], blocks: [block]), token: token)

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(stored.map(\.id), [2, 1])
    }

    /// Кейс: две одновременные синхронизации переписки (два экрана); между их началами пришёл ответ на отправку.
    /// Ожидание: сообщение защищено только в той, что началась раньше: вторая его не видела, и её сброс удаляет его.
    func test_protectedIds_arePerToken() async throws {
        try await writeState(conversationId: 1, syncMark: .stub)
        let first = await sut.beginSync(conversationId: 1)
        await sut.applySent(.make(id: 7))
        let second = await sut.beginSync(conversationId: 1)

        try await sut.applySync(.reset(firstPage: page([.make(id: 5)])), token: first)
        let afterFirst = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        try await sut.applySync(.reset(firstPage: page([.make(id: 5)])), token: second)
        let afterSecond = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)

        XCTAssertEqual(afterFirst.map(\.id), [7, 5])
        XCTAssertEqual(afterSecond.map(\.id), [5])
    }

    /// Кейс: синхронизация закончилась ошибкой (`endSync` без `applySync`), затем началась новая и записала сброс.
    /// Ожидание: id, защищённые для первой, не защищают вторую — `endSync` их очистил.
    func test_endSync_clearsProtectedIds() async throws {
        try await writeState(conversationId: 1, syncMark: .stub)
        let failed = await sut.beginSync(conversationId: 1)
        await sut.applySent(.make(id: 7))
        await sut.endSync(failed)
        let token = await sut.beginSync(conversationId: 1)

        try await sut.applySync(.reset(firstPage: page([.make(id: 5)])), token: token)

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(stored.map(\.id), [5])
    }

    // MARK: - Подгрузка

    /// Кейс: страница запрошена по `nextBlockId` 4, а кэш за это время сброшен, и продолжение стало другим.
    /// Ожидание: страница не записана — `false`.
    func test_appendOlderPage_staleBlockId_isRejected() async throws {
        try await writeState(conversationId: 1, syncMark: .stub, nextBlockId: 2)

        let isAppended = try await sut.appendOlderPage(page([.make(id: 1, blockId: 3)]), requestedBlockId: 4, conversationId: 1)

        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertFalse(isAppended)
        XCTAssertTrue(stored.isEmpty)
    }

    /// Кейс: страница запрошена по сохранённому `nextBlockId`; у сервера есть ещё более старые.
    /// Ожидание: страница записана, продолжение — `nextBlockId` страницы.
    func test_appendOlderPage_matchingBlockId_writesAndAdvancesPagination() async throws {
        try await writeState(conversationId: 1, syncMark: .stub, nextBlockId: 4)

        let older = MessagesPage(messages: [.make(id: 1, blockId: 4)], nextBlockId: 3, hasNext: true)
        let isAppended = try await sut.appendOlderPage(older, requestedBlockId: 4, conversationId: 1)

        let state = try await storage.fetchState(conversationId: 1)
        XCTAssertTrue(isAppended)
        XCTAssertEqual(state?.nextBlockId, 3)
        XCTAssertEqual(state?.hasMorePages, true)
    }

    // MARK: - Выход

    /// Кейс: переписка синхронизирована, на изменения подписан экран; начался выход из аккаунта.
    /// Ожидание: признак сброшен, поток изменений завершён, событие во время выхода не записано.
    func test_logout_clearsFlagsAndFinishesStreams() async throws {
        try await makeSynced(page: [])
        var changes = await sut.changes(conversationId: 1).makeAsyncIterator()

        await sut.prepareForLogout()
        let message = Message.make(id: 2)
        await sut.handle(.messageReceived(message, LastMessage(message: message)))
        await sut.waitForWrites()

        let isSynced = await sut.isSynced(conversationId: 1)
        let next = await changes.next()
        let stored = try await storage.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertFalse(isSynced)
        XCTAssertNil(next)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Helpers

    /// Делает переписку 1 синхронизированной в новом соединении: сброс страницей `messages`.
    /// - Parameter messages: первая страница.
    private func makeSynced(page messages: [Message]) async throws {
        monitor.connect()
        let token = await sut.beginSync(conversationId: 1)
        try await sut.applySync(.reset(firstPage: page(messages)), token: token)
        await sut.endSync(token)
    }

    /// Последняя страница переписки.
    /// - Parameter messages: сообщения, сначала самые новые.
    private func page(_ messages: [Message]) -> MessagesPage {
        MessagesPage(messages: messages, nextBlockId: nil, hasNext: false)
    }

    /// Записывает состояние кэша переписки напрямую в хранилище.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - syncMark: отметка.
    ///   - nextBlockId: продолжение подгрузки.
    private func writeState(conversationId: Int, syncMark: ServerTime, nextBlockId: Int? = nil) async throws {
        let state = MessageCacheState(syncMark: syncMark, nextBlockId: nextBlockId, hasMorePages: nextBlockId != nil)
        _ = try await storage.write(MessageStorageChanges(stateChanges: [MessageCacheStateChange(conversationId: conversationId, kind: .replace(state))]))
    }
}

/// Хранилище, запись в которое можно задержать шлагбаумом. `@unchecked Sendable`: шлагбаум задаёт тест между
/// записями.
private final class GatedMessageStorage: MessageStorageReading, MessageStorageWriting, @unchecked Sendable {
    private let storage: MessageStorageService
    /// Шлагбаум для следующих записей; `nil` — записи идут сразу.
    var gate: Gate?
    /// Число записей.
    private(set) var writeCount = 0

    /// - Parameter storage: настоящее хранилище.
    init(storage: MessageStorageService) {
        self.storage = storage
    }

    func write(_ changes: MessageStorageChanges) async throws -> [Message] {
        writeCount += 1
        if let gate {
            await gate.wait()
        }
        return try await storage.write(changes)
    }

    func fetchState(conversationId: Int) async throws -> MessageCacheState? {
        try await storage.fetchState(conversationId: conversationId)
    }

    func fetchLatestBlocks(conversationId: Int, minCount: Int) async throws -> [Message] {
        try await storage.fetchLatestBlocks(conversationId: conversationId, minCount: minCount)
    }

    func fetchBlocks(conversationId: Int, olderThan beforeBlockId: Int, minCount: Int) async throws -> [Message] {
        try await storage.fetchBlocks(conversationId: conversationId, olderThan: beforeBlockId, minCount: minCount)
    }

    func fetchMessages(conversationId: Int, fromBlockId: Int) async throws -> [Message] {
        try await storage.fetchMessages(conversationId: conversationId, fromBlockId: fromBlockId)
    }

    func cachedBlockIds(conversationId: Int, among blockIds: [Int]) async throws -> Set<Int> {
        try await storage.cachedBlockIds(conversationId: conversationId, among: blockIds)
    }
}

/// Хранилище сообщений, запись в которое всегда завершается ошибкой; чтение — из настоящего хранилища.
private final class FailingMessageStorage: MessageStorageReading, MessageStorageWriting {
    private let reading: MessageStorageReading

    /// - Parameter reading: хранилище, из которого читаются данные.
    init(reading: MessageStorageReading) {
        self.reading = reading
    }

    func fetchState(conversationId: Int) async throws -> MessageCacheState? {
        try await reading.fetchState(conversationId: conversationId)
    }

    func fetchLatestBlocks(conversationId: Int, minCount: Int) async throws -> [Message] {
        try await reading.fetchLatestBlocks(conversationId: conversationId, minCount: minCount)
    }

    func fetchBlocks(conversationId: Int, olderThan beforeBlockId: Int, minCount: Int) async throws -> [Message] {
        try await reading.fetchBlocks(conversationId: conversationId, olderThan: beforeBlockId, minCount: minCount)
    }

    func fetchMessages(conversationId: Int, fromBlockId: Int) async throws -> [Message] {
        try await reading.fetchMessages(conversationId: conversationId, fromBlockId: fromBlockId)
    }

    func cachedBlockIds(conversationId: Int, among blockIds: [Int]) async throws -> Set<Int> {
        try await reading.cachedBlockIds(conversationId: conversationId, among: blockIds)
    }

    func write(_ changes: MessageStorageChanges) async throws -> [Message] {
        throw CocoaError(.validationMultipleErrors)
    }
}
