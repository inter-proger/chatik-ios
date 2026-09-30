//
//  CoreDataStackTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class CoreDataStackTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        TemporaryFile.remove(["", "-wal", "-shm"].map { URL(fileURLWithPath: storeURL.path + $0) })
        storeURL = nil
        super.tearDown()
    }

    /// Кейс: на месте файла хранилища лежит не SQLite (файл повреждён).
    /// Ожидание: приложение не падает — хранилище создано заново и в него можно писать.
    func test_makeContainer_corruptedStore_recreatesStore() async throws {
        try Data("not a database".utf8).write(to: storeURL)

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let storage = ConversationStorageService(container: container)
        try await storage.save(conversation: .groupStub)

        let conversations = try await storage.fetchAll()
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 1)
        XCTAssertEqual(conversations, [.groupStub])
    }

    /// Кейс: хранилище исправно, контейнер открыт повторно (перезапуск приложения).
    /// Ожидание: данные на месте — пересоздаётся только хранилище, которое не открылось.
    func test_makeContainer_validStore_keepsData() async throws {
        try await ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL))
            .save(conversation: .groupStub)

        let reopened = ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL))

        let conversations = try await reopened.fetchAll()
        XCTAssertEqual(conversations, [.groupStub])
    }
}
