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

    /// Кейс: storage-сервис работает через контейнер, хранилище которого открывается в фоне; запрос пришёл сразу.
    /// Ожидание: запрос дожидается открытия хранилища — запись и чтение проходят без ошибок.
    func test_backgroundLoadedContainer_waitsForStoresBeforeQueries() async throws {
        let storeURL = storeURL!
        let storage = ConversationStorageService(container: BackgroundLoadedContainer {
            CoreDataStack.makeContainer(storeURL: storeURL)
        })

        try await storage.save(conversation: .groupStub)

        let conversations = try await storage.fetchAll()
        XCTAssertEqual(conversations, [.groupStub])
    }

    /// Кейс: хранилище создано первой версией модели (собеседник переписки — связь с `UserEntity`, без `cachedAt`).
    /// Ожидание: при открытии текущей версией данные мигрированы, а не удалены: переписки и пользователи на месте,
    /// `opponentUserId` и `cachedAt` пусты — в первой версии их не было.
    func test_makeContainer_firstModelVersion_migratesData() async throws {
        try makeStore(modelVersion: "Chatik") { context in
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

    /// Кейс: хранилище создано второй версией модели (без сообщений).
    /// Ожидание: при открытии текущей версией переписки на месте, а сообщения можно сохранять и читать.
    func test_makeContainer_secondModelVersion_migratesData() async throws {
        try makeStore(modelVersion: "Chatik 2") { context in
            let conversation = NSEntityDescription.insertNewObject(forEntityName: "ConversationEntity", into: context)
            conversation.setValue(7, forKey: "conversationId")
            conversation.setValue("group", forKey: "type")
            conversation.setValue(try JSONEncoder().encode([1, 2]), forKey: "memberIds")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let messageStorage = MessageStorageService(container: container)
        try await messageStorage.save(message: .make(id: 1, conversationId: 7))

        let conversations = try await ConversationStorageService(container: container).fetchAll()
        let messages = try await messageStorage.fetchLatest(conversationId: 7, limit: 10)
        XCTAssertEqual(conversations.map(\.id), [7])
        XCTAssertEqual(messages.map(\.id), [1])
    }

    // MARK: - Helpers

    /// Создаёт по адресу `storeURL` хранилище указанной прежней версии модели, заполняет его и закрывает.
    /// Классы Entity привязаны к текущей версии модели, поэтому прежняя версия работает с базовым `NSManagedObject`:
    /// имя класса не входит в хэш версии и на миграцию не влияет.
    /// - Parameters:
    ///   - modelVersion: имя версии модели (файла `.mom` внутри `Chatik.momd`), например `"Chatik 2"`.
    ///   - fill: заполняет контекст записями; `save()` вызывается после него.
    private func makeStore(modelVersion: String, _ fill: (NSManagedObjectContext) throws -> Void) throws {
        let modelURL = try XCTUnwrap(Bundle(for: UserEntity.self).url(forResource: "Chatik", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("\(modelVersion).mom")))
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
