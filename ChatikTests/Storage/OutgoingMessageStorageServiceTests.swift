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

        let messages = try await sut.fetchAll()
        XCTAssertEqual(messages, [message])
    }

    /// Кейс: сообщение сохранено в статусе «отправляется», затем сохранено с тем же `clientId` в статусе «не отправлено».
    /// Ожидание: в БД одна запись с новым статусом.
    func test_save_existingClientId_updatesRecord() async throws {
        try await sut.save(message: .stub(clientId: "a", status: .sending))

        try await sut.save(message: .stub(clientId: "a", status: .failed))

        let messages = try await sut.fetchAll()
        XCTAssertEqual(messages.map(\.status), [.failed])
    }

    /// Кейс: в БД сообщения двух переписок, сохранённые не по порядку отправки.
    /// Ожидание: выборка возвращает сообщения всех переписок, сначала самые старые.
    func test_fetchAll_returnsAllConversationsOldestFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_790_846_400)
        try await sut.save(message: .stub(clientId: "late", createdAt: base.addingTimeInterval(10)))
        try await sut.save(message: .stub(clientId: "other", conversationId: 2, createdAt: base.addingTimeInterval(5)))
        try await sut.save(message: .stub(clientId: "early", createdAt: base))

        let messages = try await sut.fetchAll()

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

        let messages = try await sut.fetchAll()

        XCTAssertEqual(messages.map(\.clientId), ["ok"])
    }

    /// Кейс: удаление сохранённого сообщения и сообщения, которого нет.
    /// Ожидание: сохранённое удалено, удаление несуществующего не падает.
    func test_delete_removesRecordAndIgnoresMissing() async throws {
        try await sut.save(message: .stub(clientId: "a"))

        try await sut.delete(clientId: "a")
        try await sut.delete(clientId: "missing")

        let messages = try await sut.fetchAll()
        XCTAssertTrue(messages.isEmpty)
    }

    /// Кейс: в очереди отправки есть сообщение, вызвана очистка БД при выходе.
    /// Ожидание: очередь отправки тоже очищена — следующий пользователь не увидит чужие неотправленные сообщения.
    func test_clearAll_removesOutgoingMessages() async throws {
        try await sut.save(message: .stub(clientId: "a"))

        try await LocalStorageCleaner(container: container).clearAll()

        let messages = try await sut.fetchAll()
        XCTAssertTrue(messages.isEmpty)
    }
}
