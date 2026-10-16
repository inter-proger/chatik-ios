//
//  OutgoingMessageStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class OutgoingMessageStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: OutgoingMessageStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = OutgoingMessageStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: сохранено неотправленное сообщение.
    /// Ожидание: оно читается из БД без потерь — все поля, включая статус.
    func test_save_roundTrips() async throws {
        let message = OutgoingMessage.stub(clientId: "a", status: .failed)

        try await sut.save(message: message)

        let messages = try await sut.fetchAll(senderId: 1)
        XCTAssertEqual(messages, [message])
    }

    /// Кейс: «a» первого пользователя уже сохранено; батчем сохраняются «a» и «b» первого и «a» второго,
    /// «b» в батче дважды.
    /// Ожидание: «a» первого обновлено, а не продублировано; «b» — одна запись с последней версией; «a» второго —
    /// отдельная запись.
    func test_saveMessages_upsertsByKeyAndCollapsesDuplicates() async throws {
        try await sut.save(message: .stub(clientId: "a", senderId: 1, status: .sending))
        let messages: [OutgoingMessage] = [
            .stub(clientId: "a", senderId: 1, status: .failed),
            .stub(clientId: "b", senderId: 1, text: "Старый", status: .sending),
            .stub(clientId: "a", senderId: 2, status: .sending),
            .stub(clientId: "b", senderId: 1, text: "Новый", status: .failed),
        ]

        try await sut.save(messages: messages)

        let first = try await sut.fetchAll(senderId: 1).sorted { $0.clientId < $1.clientId }
        let second = try await sut.fetchAll(senderId: 2)
        XCTAssertEqual(first.map(\.clientId), ["a", "b"])
        XCTAssertEqual(first.map(\.status), [.failed, .failed])
        XCTAssertEqual(first.last?.text, "Новый")
        XCTAssertEqual(second.map(\.clientId), ["a"])
    }

    /// Кейс: сообщение сохранено в статусе «отправляется», затем сохранено с тем же `clientId` в статусе «не отправлено».
    /// Ожидание: в БД одна запись с новым статусом.
    func test_save_existingClientId_updatesRecord() async throws {
        try await sut.save(message: .stub(clientId: "a", status: .sending))

        try await sut.save(message: .stub(clientId: "a", status: .failed))

        let messages = try await sut.fetchAll(senderId: 1)
        XCTAssertEqual(messages.map(\.status), [.failed])
    }

    /// Кейс: в БД сообщения двух переписок, сохранённые не по порядку отправки.
    /// Ожидание: выборка возвращает сообщения всех переписок, сначала самые старые.
    func test_fetchAll_returnsAllConversationsOldestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_790_846_400)
        try await sut.save(message: .stub(clientId: "late", createdAt: base.addingTimeInterval(10)))
        try await sut.save(message: .stub(clientId: "other", conversationId: 2, createdAt: base.addingTimeInterval(5)))
        try await sut.save(message: .stub(clientId: "early", createdAt: base))

        let messages = try await sut.fetchAll(senderId: 1)

        XCTAssertEqual(messages.map(\.clientId), ["early", "other", "late"])
    }

    /// Кейс: в БД есть запись с неизвестным статусом и запись без текста.
    /// Ожидание: выборка их пропускает, корректная запись возвращается.
    func test_fetchAll_skipsBrokenRecords() async throws {
        try await sut.save(message: .stub(clientId: "ok"))
        try await container.performWrite { context in
            let unknownStatus = OutgoingMessageEntity(context: context)
            unknownStatus.update(from: .stub(clientId: "status"))
            unknownStatus.status = "delivered"
            let noText = OutgoingMessageEntity(context: context)
            noText.update(from: .stub(clientId: "text"))
            noText.text = nil
            try context.save()
        }

        let messages = try await sut.fetchAll(senderId: 1)

        XCTAssertEqual(messages.map(\.clientId), ["ok"])
    }

    /// Кейс: удаление сохранённого сообщения и сообщения, которого нет.
    /// Ожидание: сохранённое удалено, удаление несуществующего не падает.
    func test_delete_removesRecordAndIgnoresMissing() async throws {
        try await sut.save(message: .stub(clientId: "a"))

        try await sut.delete(senderId: 1, clientId: "a")
        try await sut.delete(senderId: 1, clientId: "missing")

        let messages = try await sut.fetchAll(senderId: 1)
        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - Несколько пользователей

    /// Кейс: два пользователя сохранили сообщения с одинаковым `clientId`.
    /// Ожидание: в БД две записи — ключ уникален только в паре с отправителем; каждый читает своё.
    func test_save_sameClientIdDifferentSenders_keepsBoth() async throws {
        try await sut.save(message: .stub(clientId: "a", senderId: 1, text: "Первого"))

        try await sut.save(message: .stub(clientId: "a", senderId: 2, text: "Второго"))

        let first = try await sut.fetchAll(senderId: 1)
        let second = try await sut.fetchAll(senderId: 2)
        XCTAssertEqual(first.map(\.text), ["Первого"])
        XCTAssertEqual(second.map(\.text), ["Второго"])
    }

    /// Кейс: в БД сообщения двух пользователей вперемешку по времени.
    /// Ожидание: выборка возвращает только сообщения переданного пользователя, сначала самые старые.
    func test_fetchAll_returnsOnlySenderMessagesOldestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_790_846_400)
        try await sut.save(message: .stub(clientId: "late", senderId: 1, createdAt: base.addingTimeInterval(10)))
        try await sut.save(message: .stub(clientId: "foreign", senderId: 2, createdAt: base.addingTimeInterval(5)))
        try await sut.save(message: .stub(clientId: "early", senderId: 1, createdAt: base))

        let messages = try await sut.fetchAll(senderId: 1)

        XCTAssertEqual(messages.map(\.clientId), ["early", "late"])
    }

    /// Кейс: два пользователя сохранили сообщения с одинаковым `clientId`; первый удаляет своё.
    /// Ожидание: удалено только сообщение первого, сообщение второго на месте.
    func test_delete_removesOnlySenderMessage() async throws {
        try await sut.save(message: .stub(clientId: "a", senderId: 1))
        try await sut.save(message: .stub(clientId: "a", senderId: 2))

        try await sut.delete(senderId: 1, clientId: "a")

        let first = try await sut.fetchAll(senderId: 1)
        let second = try await sut.fetchAll(senderId: 2)
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second.map(\.clientId), ["a"])
    }

    /// Кейс: у двух пользователей сообщения раньше границы, на границе и позже; удаление просроченных.
    /// Ожидание: удалены сообщения обоих пользователей раньше границы; на границе и позже — на месте.
    func test_deleteAllCreatedBefore_removesOlderOfAllSenders() async throws {
        let boundary = Date(timeIntervalSince1970: 1_790_846_400)
        let messages: [OutgoingMessage] = [
            .stub(clientId: "old1", senderId: 1, createdAt: boundary.addingTimeInterval(-1)),
            .stub(clientId: "old2", senderId: 2, createdAt: boundary.addingTimeInterval(-100)),
            .stub(clientId: "edge", senderId: 1, createdAt: boundary),
            .stub(clientId: "new2", senderId: 2, createdAt: boundary.addingTimeInterval(1)),
        ]
        for message in messages {
            try await sut.save(message: message)
        }

        try await sut.deleteAll(createdBefore: boundary)

        let first = try await sut.fetchAll(senderId: 1)
        let second = try await sut.fetchAll(senderId: 2)
        XCTAssertEqual(first.map(\.clientId), ["edge"])
        XCTAssertEqual(second.map(\.clientId), ["new2"])
    }

    /// Кейс: в очереди отправки есть сообщение, вызвана очистка БД при выходе.
    /// Ожидание: очередь отправки не очищена — неотправленные сообщения переживают выход.
    func test_clearAll_keepsOutgoingMessages() async throws {
        try await sut.save(message: .stub(clientId: "a"))

        try await LocalStorageCleaner(container: container).clearAll()

        let messages = try await sut.fetchAll(senderId: 1)
        XCTAssertEqual(messages.map(\.clientId), ["a"])
    }
}
