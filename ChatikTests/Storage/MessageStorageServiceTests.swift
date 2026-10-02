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

    // MARK: - Сохранение

    /// Кейс: сохранено отредактированное сообщение.
    /// Ожидание: оно читается из БД без потерь — все поля, включая `isEdited` и обе даты.
    func test_saveMessage_roundTrips() async throws {
        try await sut.save(message: .editedStub)

        let found = try await sut.find(byId: Message.editedStub.id)

        XCTAssertEqual(found, .editedStub)
    }

    /// Кейс: сообщение сохранено, затем сохранено повторно с тем же `messageId` после редактирования.
    /// Ожидание: в БД одна запись с новым текстом.
    func test_save_existingId_updatesRecord() async throws {
        try await sut.save(message: .stub)

        try await sut.save(message: .editedStub)

        let messages = try await sut.fetchLatest(conversationId: Message.stub.conversationId, limit: 10)
        XCTAssertEqual(messages, [.editedStub])
    }

    /// Кейс: батч из трёх сообщений, два из них с одинаковым `messageId`.
    /// Ожидание: сохранены две записи, для повторного `messageId` — последняя версия.
    func test_saveMessages_duplicateIds_collapsesToLast() async throws {
        let messages = [
            Message.make(id: 1, text: "Первый"),
            Message.make(id: 2, text: "Второй"),
            Message.make(id: 1, text: "Первый, исправленный"),
        ]

        try await sut.save(messages: messages)

        let saved = try await sut.fetchLatest(conversationId: 1, limit: 10)
        XCTAssertEqual(saved.map(\.text), ["Второй", "Первый, исправленный"])
    }

    // MARK: - Выборка

    /// Кейс: в БД сообщения двух переписок, сохранённые не по порядку.
    /// Ожидание: выборка возвращает сообщения только запрошенной переписки по убыванию `messageId`.
    func test_fetchLatest_filtersByConversationAndSortsNewestFirst() async throws {
        try await sut.save(messages: [
            .make(id: 2, conversationId: 1),
            .make(id: 5, conversationId: 2),
            .make(id: 3, conversationId: 1),
            .make(id: 1, conversationId: 1),
        ])

        let messages = try await sut.fetchLatest(conversationId: 1, limit: 10)

        XCTAssertEqual(messages.map(\.id), [3, 2, 1])
    }

    /// Кейс: в переписке сообщений больше лимита.
    /// Ожидание: возвращаются только самые новые в пределах лимита.
    func test_fetchLatest_respectsLimit() async throws {
        try await sut.save(messages: (1...5).map { Message.make(id: $0) })

        let messages = try await sut.fetchLatest(conversationId: 1, limit: 2)

        XCTAssertEqual(messages.map(\.id), [5, 4])
    }

    /// Кейс: в БД есть запись сообщения без обязательного поля `text`.
    /// Ожидание: выборка её пропускает, остальные записи возвращаются.
    func test_fetchLatest_skipsBrokenRecords() async throws {
        try await sut.save(message: .make(id: 1))
        try await container.performWrite { context in
            let broken = MessageEntity(context: context)
            broken.messageId = 2
            broken.conversationId = 1
            broken.type = MessageType.text.rawValue
            broken.createdAt = .distantPast
            broken.updatedAt = .distantPast
            try context.save()
        }

        let messages = try await sut.fetchLatest(conversationId: 1, limit: 10)

        XCTAssertEqual(messages.map(\.id), [1])
    }

    /// Кейс: в БД сообщение с типом, которого клиент не знает.
    /// Ожидание: оно читается как `.unknown`, а не отбрасывается.
    func test_fetchLatest_unknownType_readsAsUnknown() async throws {
        try await sut.save(message: .make(id: 1))
        try await container.performWrite { context in
            let entity = try XCTUnwrap(context.fetch(MessageEntity.makeFetchRequest(id: 1)).first)
            entity.type = "sticker"
            try context.save()
        }

        let messages = try await sut.fetchLatest(conversationId: 1, limit: 10)

        XCTAssertEqual(messages.map(\.type), [.unknown])
    }

    // MARK: - Поиск и удаление

    /// Кейс: поиск и удаление по `messageId`, которого нет в БД.
    /// Ожидание: поиск возвращает `nil`, удаление не падает и не трогает другие записи.
    func test_findAndDelete_missingId_doNotFail() async throws {
        try await sut.save(message: .make(id: 1))

        let found = try await sut.find(byId: 42)
        try await sut.delete(byId: 42)

        let messages = try await sut.fetchLatest(conversationId: 1, limit: 10)
        XCTAssertNil(found)
        XCTAssertEqual(messages.map(\.id), [1])
    }

    /// Кейс: удаление сохранённого сообщения.
    /// Ожидание: оно больше не находится.
    func test_delete_existingId_removesRecord() async throws {
        try await sut.save(message: .make(id: 1))

        try await sut.delete(byId: 1)

        let found = try await sut.find(byId: 1)
        XCTAssertNil(found)
    }
}
