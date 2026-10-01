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

    /// Кейс: хранилище создано первой версией модели (собеседник переписки — связь с `UserEntity`, без `cachedAt`).
    /// Ожидание: при открытии текущей версией данные мигрированы, а не удалены: переписки и пользователи на месте,
    /// `opponentUserId` и `cachedAt` пусты — в первой версии их не было.
    func test_makeContainer_firstModelVersion_migratesData() async throws {
        try makeStoreWithFirstModelVersion { context in
            let user = NSEntityDescription.insertNewObject(forEntityName: "UserEntity", into: context)
            user.setValue(2, forKey: "userId")
            user.setValue("petr", forKey: "login")
            user.setValue("Petr", forKey: "name")
            let conversation = NSEntityDescription.insertNewObject(forEntityName: "ConversationEntity", into: context)
            conversation.setValue(7, forKey: "conversationId")
            conversation.setValue("single", forKey: "type")
            conversation.setValue(try JSONEncoder().encode([1, 2]), forKey: "memberIds")
            conversation.setValue(user, forKey: "opponentUser")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)

        let conversations = try await ConversationStorageService(container: container).fetchAll()
        let users = try await UserStorageService(container: container).findStored(byIds: [2])
        XCTAssertEqual(conversations.map(\.id), [7])
        XCTAssertNil(conversations.first?.opponentUserId)
        XCTAssertEqual(users, [StoredUser(user: User(userId: 2, login: "petr", name: "Petr", avatar: nil), cachedAt: .distantPast)])
    }

    // MARK: - Helpers

    /// Создаёт по адресу `storeURL` хранилище первой версии модели, заполняет его и закрывает.
    /// Классы Entity привязаны к текущей версии модели, поэтому первая версия работает с базовым `NSManagedObject`:
    /// имя класса не входит в хэш версии и на миграцию не влияет.
    /// - Parameter fill: заполняет контекст записями; `save()` вызывается после него.
    private func makeStoreWithFirstModelVersion(_ fill: (NSManagedObjectContext) throws -> Void) throws {
        let modelURL = try XCTUnwrap(Bundle(for: UserEntity.self).url(forResource: "Chatik", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("Chatik.mom")))
        model.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            try fill(context)
            try context.save()
        }
        try coordinator.remove(store)
    }
}
