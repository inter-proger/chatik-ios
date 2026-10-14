//
//  MessageStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class MessageStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: MessageStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = MessageStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Upsert

    /// Кейс: записано отредактированное сообщение.
    /// Ожидание: оно читается из БД без потерь — все поля, включая `isEdited` и обе даты; запись вернула его версию.
    func test_write_upsert_roundTrips() async throws {
        let written = try await sut.write(MessageStorageChanges(upserts: [.editedStub]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)

        XCTAssertEqual(written, [.editedStub])
        XCTAssertEqual(messages, [.editedStub])
    }

    /// Кейс: в БД отредактированное сообщение (пришло событием WebSocket), затем записывается более старая версия
    /// (ответ REST, собранный до правки).
    /// Ожидание: запись не откатилась, и запись вернула версию, оставшуюся в БД.
    func test_write_olderVersion_keepsNewerRecord() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.editedStub]))

        let written = try await sut.write(MessageStorageChanges(upserts: [.stub]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(written, [.editedStub])
        XCTAssertEqual(messages, [.editedStub])
    }

    /// Кейс: обновление только существующих — для сообщения, которое есть в БД, и для отсутствующего.
    /// Ожидание: существующее обновлено, отсутствующее не создано; запись вернула только обновлённое.
    func test_write_updatesOfExisting_doesNotCreateMissing() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.stub]))

        let written = try await sut.write(MessageStorageChanges(updatesOfExisting: [.editedStub, .make(id: 99)]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(written, [.editedStub])
        XCTAssertEqual(messages, [.editedStub])
    }

    /// Кейс: в очереди отправки два сообщения с одним `clientId` — текущего пользователя и (теоретически) другого
    /// отправителя; подтверждено серверное сообщение текущего пользователя с этим `clientId`.
    /// Ожидание: удалена только неотправленная копия того же отправителя — `clientId` сравнивается вместе с `senderId`.
    func test_write_confirmed_removesOutgoingOfSameSender() async throws {
        let outgoingStorage = OutgoingMessageStorageService(container: container)
        try await outgoingStorage.save(message: .stub(clientId: "a", senderId: 1))
        try await outgoingStorage.save(message: .stub(clientId: "b", senderId: 1))

        _ = try await sut.write(MessageStorageChanges(confirmed: [.make(id: 1, senderId: 1, clientId: "a"), .make(id: 2, senderId: 2, clientId: "b")]))

        let outgoing = try await outgoingStorage.fetchAll()
        XCTAssertEqual(outgoing.map(\.clientId), ["b"])
    }

    // MARK: - Замена

    /// Кейс: в кэше переписки сообщения 1–3 и сообщение другой переписки; кэш заменяется страницей из 3 и 4,
    /// сообщение 2 защищено.
    /// Ожидание: остались 4, 3 и защищённое 2; 1 удалено; другая переписка не тронута.
    func test_write_replacedConversation_deletesAllButPageAndProtected() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.make(id: 1), .make(id: 2), .make(id: 3), .make(id: 9, conversationId: 2)]))

        _ = try await sut.write(MessageStorageChanges(
            upserts: [.make(id: 3), .make(id: 4)],
            replacedConversationId: 1,
            protectedMessageIds: [2]
        ))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)
        let other = try await sut.fetchLatestBlocks(conversationId: 2, minCount: 10)
        XCTAssertEqual(messages.map(\.id), [4, 3, 2])
        XCTAssertEqual(other.map(\.id), [9])
    }

    /// Кейс: блок 2 в кэше — сообщения 3, 4, 5; блок 1 — сообщение 1; блок 2 применяется целиком из ответа
    /// с отредактированным 4 и без 3 и 5, а 5 защищено.
    /// Ожидание: 3 удалено, 4 обновлено, защищённое 5 осталось; блок 1 не тронут.
    func test_write_replacedBlock_deletesMissingMessagesOfBlock() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [
            .make(id: 1, blockId: 1),
            .make(id: 3, blockId: 2),
            .make(id: 4, blockId: 2),
            .make(id: 5, blockId: 2),
        ]))
        let edited = Message.make(id: 4, text: "Исправлено", blockId: 2, updatedAt: .stub(60_000))
        let block = MessageBlock(blockId: 2, conversationId: 1, messages: [edited], updatedAt: .stub(60_000))

        _ = try await sut.write(MessageStorageChanges(replacedBlocks: [block], protectedMessageIds: [5]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(messages.map(\.id), [5, 4, 1])
        XCTAssertEqual(messages.first { $0.id == 4 }?.text, "Исправлено")
    }

    /// Кейс: блок из ответа пуст — все его сообщения удалены на сервере.
    /// Ожидание: сообщения блока удалены из кэша.
    func test_write_emptyReplacedBlock_clearsBlock() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.make(id: 1, blockId: 1), .make(id: 2, blockId: 2)]))

        _ = try await sut.write(MessageStorageChanges(replacedBlocks: [MessageBlock(blockId: 1, conversationId: 1, messages: [], updatedAt: nil)]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)
        XCTAssertEqual(messages.map(\.id), [2])
    }

    // MARK: - Состояние кэша

    /// Кейс: состояние записано целиком, затем отметка сдвинута вперёд, назад и задана пагинация.
    /// Ожидание: отметка — максимум, пагинация — последняя заданная.
    func test_write_stateChanges_applyInOrder() async throws {
        let initial = MessageCacheState(syncMark: .stub(1000), nextBlockId: 5, hasMorePages: true)

        _ = try await sut.write(MessageStorageChanges(stateChanges: [
            MessageCacheStateChange(conversationId: 1, kind: .replace(initial)),
            MessageCacheStateChange(conversationId: 1, kind: .advanceSyncMark(.stub(3000))),
            MessageCacheStateChange(conversationId: 1, kind: .advanceSyncMark(.stub(2000))),
            MessageCacheStateChange(conversationId: 1, kind: .setPagination(nextBlockId: nil, hasMorePages: false)),
        ]))

        let state = try await sut.fetchState(conversationId: 1)
        XCTAssertEqual(state, MessageCacheState(syncMark: .stub(3000), nextBlockId: nil, hasMorePages: false))
    }

    /// Кейс: сдвиг отметки и пагинация для переписки без записи о состоянии.
    /// Ожидание: состояние не создаётся — переписка без кэша остаётся без кэша.
    func test_write_advanceWithoutState_doesNotCreateState() async throws {
        _ = try await sut.write(MessageStorageChanges(stateChanges: [
            MessageCacheStateChange(conversationId: 1, kind: .advanceSyncMark(.stub(3000))),
            MessageCacheStateChange(conversationId: 1, kind: .setPagination(nextBlockId: 2, hasMorePages: true)),
        ]))

        let state = try await sut.fetchState(conversationId: 1)
        XCTAssertNil(state)
    }

    // MARK: - Чтение окна

    /// Кейс: в переписке блоки 3 (сообщения 5, 6), 2 (3, 4) и 1 (1, 2) и сообщение другой переписки; нужно
    /// не меньше 3 сообщений.
    /// Ожидание: прочитаны блоки 3 и 2 целиком — 4 сообщения по убыванию `messageId`.
    func test_fetchLatestBlocks_readsWholeBlocks() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: makeBlocks() + [.make(id: 99, conversationId: 2, blockId: 3)]))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 3)

        XCTAssertEqual(messages.map(\.id), [6, 5, 4, 3])
    }

    /// Кейс: блоки старше блока 3, не меньше 1 сообщения.
    /// Ожидание: прочитан блок 2 целиком.
    func test_fetchBlocksOlderThan_readsNextWholeBlock() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: makeBlocks()))

        let messages = try await sut.fetchBlocks(conversationId: 1, olderThan: 3, minCount: 1)

        XCTAssertEqual(messages.map(\.id), [4, 3])
    }

    /// Кейс: в кэше меньше сообщений, чем нужно.
    /// Ожидание: прочитаны все.
    func test_fetchLatestBlocks_fewerThanMinCount_readsAll() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: makeBlocks()))

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 50)

        XCTAssertEqual(messages.map(\.id), [6, 5, 4, 3, 2, 1])
    }

    /// Кейс: перечитывание окна с блока 2.
    /// Ожидание: блоки 3 и 2.
    func test_fetchMessagesFromBlock_readsBlockAndNewer() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: makeBlocks()))

        let messages = try await sut.fetchMessages(conversationId: 1, fromBlockId: 2)

        XCTAssertEqual(messages.map(\.id), [6, 5, 4, 3])
    }

    /// Кейс: какие из блоков 1, 2, 7 есть в кэше переписки.
    /// Ожидание: 1 и 2.
    func test_cachedBlockIds_returnsOnlyCached() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: makeBlocks() + [.make(id: 99, conversationId: 2, blockId: 7)]))

        let cached = try await sut.cachedBlockIds(conversationId: 1, among: [1, 2, 7])

        XCTAssertEqual(cached, [1, 2])
    }

    /// Кейс: в БД есть запись сообщения без обязательного поля `text` и запись без `clientId`.
    /// Ожидание: чтение их пропускает, остальные записи возвращаются.
    func test_fetchLatestBlocks_skipsBrokenRecords() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.make(id: 1)]))
        try await container.performWrite { context in
            let broken = MessageEntity(context: context)
            broken.messageId = 2
            broken.conversationId = 1
            broken.type = MessageType.text.rawValue
            let legacy = MessageEntity(context: context)
            legacy.update(from: .make(id: 3))
            legacy.clientId = nil
            try context.save()
        }

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)

        XCTAssertEqual(messages.map(\.id), [1])
    }

    /// Кейс: в БД сообщение с типом, которого клиент не знает.
    /// Ожидание: оно читается как `.unknown`, а не отбрасывается.
    func test_fetchLatestBlocks_unknownType_readsAsUnknown() async throws {
        _ = try await sut.write(MessageStorageChanges(upserts: [.make(id: 1)]))
        try await container.performWrite { context in
            let entity = try XCTUnwrap(context.fetch(MessageEntity.makeFetchRequest(id: 1)).first)
            entity.type = "sticker"
            try context.save()
        }

        let messages = try await sut.fetchLatestBlocks(conversationId: 1, minCount: 10)

        XCTAssertEqual(messages.map(\.type), [.unknown])
    }

    // MARK: - Helpers

    /// Сообщения переписки 1: блок 1 — 1, 2; блок 2 — 3, 4; блок 3 — 5, 6.
    private func makeBlocks() -> [Message] {
        (1...6).map { Message.make(id: $0, blockId: ($0 + 1) / 2) }
    }
}
