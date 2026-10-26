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
        try await storage.save(conversations: [.groupStub], state: ConversationListState())

        let stored = try await storage.fetchList()
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 1)
        XCTAssertEqual(stored.conversations, [.groupStub])
    }

    /// Кейс: хранилище исправно, контейнер открыт повторно (перезапуск приложения).
    /// Ожидание: данные и состояние синхронизации на месте — пересоздаётся только хранилище, которое не открылось,
    /// а очистка кэша со временем в секундах не трогает хранилище текущей версии.
    func test_makeContainer_validStore_keepsData() async throws {
        let state = ConversationListState(isLoaded: true, hasMorePages: true, positionWatermark: .stub, positionWatermarkCeiling: nil, syncedChangeVersion: 7)
        try await ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL))
            .save(conversations: [.groupStub], state: state)

        let reopened = ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL))

        let stored = try await reopened.fetchList()
        XCTAssertEqual(stored.conversations, [.groupStub])
        XCTAssertEqual(stored.state, state)
    }

    /// Кейс: storage-сервис работает через контейнер, хранилище которого открывается в фоне; запрос пришёл сразу.
    /// Ожидание: запрос дожидается открытия хранилища — запись и чтение проходят без ошибок.
    func test_backgroundLoadedContainer_waitsForStoresBeforeQueries() async throws {
        let storeURL = storeURL!
        let storage = ConversationStorageService(container: BackgroundLoadedContainer {
            CoreDataStack.makeContainer(storeURL: storeURL)
        })

        try await storage.save(conversations: [.groupStub], state: ConversationListState())

        let stored = try await storage.fetchList()
        XCTAssertEqual(stored.conversations, [.groupStub])
    }

    /// Кейс: хранилище создано пятой версией модели — время в секундах; в нём переписка, сообщение,
    /// неотправленное сообщение и пользователь.
    /// Ожидание: хранилище мигрировано, а не пересоздано: переписки и сообщения со старым временем удалены,
    /// очередь отправки и пользователи на месте, новые сообщения сохраняются.
    func test_makeContainer_fifthModelVersion_clearsServerTimeCacheAndKeepsOutgoing() async throws {
        try makeStore(modelVersion: "Chatik 5") { context in
            try self.insertConversation(id: 7, into: context)
            let message = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            message.setValue(1, forKey: "messageId")
            message.setValue(7, forKey: "conversationId")
            message.setValue("c1", forKey: "clientId")
            message.setValue("text", forKey: "type")
            message.setValue("Старое", forKey: "text")
            message.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "createdAt")
            message.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "updatedAt")
            let outgoing = NSEntityDescription.insertNewObject(forEntityName: "OutgoingMessageEntity", into: context)
            outgoing.setValue("pending", forKey: "clientId")
            outgoing.setValue(7, forKey: "conversationId")
            outgoing.setValue(1, forKey: "senderId")
            outgoing.setValue("Не отправлено", forKey: "text")
            outgoing.setValue("failed", forKey: "status")
            outgoing.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "createdAt")
            try self.insertUser(id: 2, into: context)
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let messageStorage = MessageStorageService(container: container)
        let messages = try await messageStorage.fetchLatestBlocks(conversationId: 7, minCount: 10)
        _ = try await messageStorage.write(MessageStorageChanges(upserts: [.make(id: 2, conversationId: 7)]))

        let stored = try await ConversationStorageService(container: container).fetchList()
        let outgoing = try await OutgoingMessageStorageService(container: container).fetchAll(senderId: 1)
        let users = try await UserStorageService(container: container).findStored(byIds: [2])
        let saved = try await messageStorage.fetchLatestBlocks(conversationId: 7, minCount: 10)
        XCTAssertTrue(stored.conversations.isEmpty)
        XCTAssertEqual(stored.state, ConversationListState())
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(outgoing.map(\.clientId), ["pending"])
        XCTAssertEqual(users.map(\.user.userId), [2])
        XCTAssertEqual(saved.map(\.id), [2])
    }

    /// Кейс: хранилище создано первой версией модели (собеседник переписки — связь с `UserEntity`, без `cachedAt`).
    /// Ожидание: хранилище мигрировано: пользователи на месте (`cachedAt` пуст — в первой версии его не было),
    /// а переписки удалены — время в них в секундах.
    func test_makeContainer_firstModelVersion_migratesUsersAndClearsConversations() async throws {
        try makeStore(modelVersion: "Chatik") { context in
            let user = try self.insertUser(id: 2, into: context)
            let conversation = try self.insertConversation(id: 7, into: context)
            conversation.setValue(user, forKey: "opponentUser")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)

        let stored = try await ConversationStorageService(container: container).fetchList()
        let users = try await UserStorageService(container: container).findStored(byIds: [2])
        XCTAssertTrue(stored.conversations.isEmpty)
        XCTAssertEqual(users, [StoredUser(user: User(userId: 2, login: "petr", name: "Petr", avatar: nil), cachedAt: .distantPast)])
    }

    /// Кейс: хранилище создано второй версией модели (без сообщений).
    /// Ожидание: хранилище мигрировано — сообщения можно сохранять и читать; переписки со временем в секундах удалены.
    func test_makeContainer_secondModelVersion_migratesStore() async throws {
        try makeStore(modelVersion: "Chatik 2") { context in
            try self.insertConversation(id: 7, into: context)
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let messageStorage = MessageStorageService(container: container)
        _ = try await messageStorage.write(MessageStorageChanges(upserts: [.make(id: 1, conversationId: 7)]))

        let stored = try await ConversationStorageService(container: container).fetchList()
        let messages = try await messageStorage.fetchLatestBlocks(conversationId: 7, minCount: 10)
        XCTAssertTrue(stored.conversations.isEmpty)
        XCTAssertEqual(messages.map(\.id), [1])
    }

    /// Кейс: хранилище создано шестой версией модели (время в миллисекундах, без состояния кэша сообщений);
    /// в нём сообщение.
    /// Ожидание: лёгкая миграция без очистки — сообщение на месте, у переписки нет состояния кэша, и его можно записать.
    func test_makeContainer_sixthModelVersion_keepsMessagesAndAddsCacheState() async throws {
        try makeStore(modelVersion: "Chatik 6") { context in
            let message = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            message.setValue(1, forKey: "messageId")
            message.setValue(7, forKey: "conversationId")
            message.setValue(3, forKey: "blockId")
            message.setValue("c1", forKey: "clientId")
            message.setValue("text", forKey: "type")
            message.setValue("Сохранённое", forKey: "text")
            message.setValue(1_790_846_400_000, forKey: "createdAtMs")
            message.setValue(1_790_846_400_000, forKey: "updatedAtMs")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let messageStorage = MessageStorageService(container: container)
        let messages = try await messageStorage.fetchLatestBlocks(conversationId: 7, minCount: 10)
        let stateBefore = try await messageStorage.fetchState(conversationId: 7)
        let state = MessageCacheState(syncMark: ServerTime(milliseconds: 1), nextBlockId: nil, hasMorePages: false)
        _ = try await messageStorage.write(MessageStorageChanges(stateChanges: [MessageCacheStateChange(conversationId: 7, kind: .replace(state))]))

        let stateAfter = try await messageStorage.fetchState(conversationId: 7)
        XCTAssertEqual(messages.map(\.text), ["Сохранённое"])
        XCTAssertNil(stateBefore)
        XCTAssertEqual(stateAfter, state)
    }

    /// Кейс: хранилище создано седьмой версией модели (без черновиков); в нём сообщение и неотправленное сообщение.
    /// Ожидание: лёгкая миграция без очистки — данные на месте, черновики можно записать и прочитать.
    func test_makeContainer_seventhModelVersion_keepsDataAndAddsDrafts() async throws {
        try makeStore(modelVersion: "Chatik 7") { context in
            let message = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            message.setValue(1, forKey: "messageId")
            message.setValue(7, forKey: "conversationId")
            message.setValue(3, forKey: "blockId")
            message.setValue("c1", forKey: "clientId")
            message.setValue("text", forKey: "type")
            message.setValue("Сохранённое", forKey: "text")
            message.setValue(1_790_846_400_000, forKey: "createdAtMs")
            message.setValue(1_790_846_400_000, forKey: "updatedAtMs")
            let outgoing = NSEntityDescription.insertNewObject(forEntityName: "OutgoingMessageEntity", into: context)
            outgoing.setValue("pending", forKey: "clientId")
            outgoing.setValue(7, forKey: "conversationId")
            outgoing.setValue(1, forKey: "senderId")
            outgoing.setValue("Не отправлено", forKey: "text")
            outgoing.setValue("failed", forKey: "status")
            outgoing.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "createdAt")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let drafts = MessageDraftStorageService(container: container)
        try await drafts.apply([7: .draft("Черновик")], userId: 1)

        let messages = try await MessageStorageService(container: container).fetchLatestBlocks(conversationId: 7, minCount: 10)
        let outgoing = try await OutgoingMessageStorageService(container: container).fetchAll(senderId: 1)
        let storedDrafts = try await drafts.fetchAll(userId: 1).mapValues(\.text)
        XCTAssertEqual(messages.map(\.text), ["Сохранённое"])
        XCTAssertEqual(outgoing.map(\.clientId), ["pending"])
        XCTAssertEqual(storedDrafts, [7: "Черновик"])
    }

    /// Кейс: хранилище создано восьмой версией модели — очередь отправки уникальна по одному `clientId`; в нём
    /// неотправленное сообщение пользователя 1.
    /// Ожидание: лёгкая миграция без потери данных — сообщение на месте, и действует новое ограничение
    /// уникальности `(senderId, clientId)`: сообщение пользователя 2 с тем же `clientId` сохраняется отдельной
    /// записью, а не заменяет первое.
    func test_makeContainer_eighthModelVersion_keepsOutgoingAndAppliesSenderConstraint() async throws {
        try makeStore(modelVersion: "Chatik 8") { context in
            let outgoing = NSEntityDescription.insertNewObject(forEntityName: "OutgoingMessageEntity", into: context)
            outgoing.setValue("pending", forKey: "clientId")
            outgoing.setValue(7, forKey: "conversationId")
            outgoing.setValue(1, forKey: "senderId")
            outgoing.setValue("Не отправлено", forKey: "text")
            outgoing.setValue("failed", forKey: "status")
            outgoing.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "createdAt")
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let storage = OutgoingMessageStorageService(container: container)
        try await storage.save(message: .stub(clientId: "pending", senderId: 2, text: "Другого пользователя"))

        let first = try await storage.fetchAll(senderId: 1)
        let second = try await storage.fetchAll(senderId: 2)
        XCTAssertEqual(first.map(\.text), ["Не отправлено"])
        XCTAssertEqual(second.map(\.text), ["Другого пользователя"])
    }

    /// Кейс: хранилище создано девятой версией модели (черновики без правок); в нём черновики двух переписок.
    /// Ожидание: лёгкая миграция без потери данных — черновики на месте и без правок, а правку можно записать
    /// рядом с черновиком и прочитать.
    func test_makeContainer_ninthModelVersion_keepsDraftsAndAddsEdits() async throws {
        try makeStore(modelVersion: "Chatik 9") { context in
            for (conversationId, text) in [(7, "Первый"), (8, "Второй")] {
                let draft = NSEntityDescription.insertNewObject(forEntityName: "MessageDraftEntity", into: context)
                draft.setValue(1, forKey: "userId")
                draft.setValue(conversationId, forKey: "conversationId")
                draft.setValue(text, forKey: "text")
                draft.setValue(Date(timeIntervalSince1970: 1_790_846_400), forKey: "updatedAt")
            }
        }

        let container = CoreDataStack.makeContainer(storeURL: storeURL)
        let drafts = MessageDraftStorageService(container: container)
        let migrated = try await drafts.fetchAll(userId: 1)
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")
        try await drafts.apply([7: .edit(edit)], userId: 1)

        let stored = try await drafts.fetchAll(userId: 1)
        XCTAssertEqual(migrated, [7: MessageDraft(text: "Первый"), 8: MessageDraft(text: "Второй")])
        XCTAssertEqual(stored[7], MessageDraft(text: "Первый", edit: edit))
    }

    /// Кейс: хранилище создано десятой версией модели (без прочтения); в нём переписка и состояние загруженного списка
    /// с водяными знаками позиции и информации.
    /// Ожидание: лёгкая миграция без потери данных — переписка на месте с нулевым прочтением, водяной знак позиции
    /// сохранён, а курсора изменений нет: следующая синхронизация будет полной загрузкой.
    func test_makeContainer_tenthModelVersion_keepsListAndRequiresFullLoad() async throws {
        try makeStore(modelVersion: "Chatik 10") { context in
            let conversation = try self.insertConversation(id: 7, into: context)
            conversation.setValue(1_790_846_400_000, forKey: "positionUpdatedAt")
            let state = NSEntityDescription.insertNewObject(forEntityName: "ConversationListStateEntity", into: context)
            state.setValue(true, forKey: "isLoaded")
            state.setValue(1_790_846_400_000, forKey: "positionWatermark")
            state.setValue(1_790_846_400_000, forKey: "infoWatermark")
        }

        let stored = try await ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL)).fetchList()

        XCTAssertEqual(stored.conversations.map(\.conversationId), [7])
        XCTAssertEqual(stored.conversations.first?.readState, ConversationReadState(unreadCount: 0, lastReadMessageId: 0, changeVersion: 0))
        XCTAssertEqual(stored.state.positionWatermark, ServerTime(milliseconds: 1_790_846_400_000))
        XCTAssertNil(stored.state.syncedChangeVersion)
        XCTAssertEqual(stored.state.totalUnreadCount, 0)
    }

    /// Кейс: хранилище создано двенадцатой версией модели; в нём группа с последним сообщением и загруженный список.
    /// Ожидание: лёгкая миграция без очистки: переписка и курсор на месте, отправитель последнего сообщения
    /// неизвестен (0), меток удаления и ожидающих групп нет.
    func test_makeContainer_twelfthModelVersion_keepsListWithUnknownSender() async throws {
        try makeStore(modelVersion: "Chatik 12") { context in
            let conversation = try self.insertConversation(id: 7, into: context)
            conversation.setValue(15, forKey: "lastMessageId")
            conversation.setValue("text", forKey: "lastMessageType")
            conversation.setValue(1_790_846_400_000, forKey: "lastMessageUpdatedAt")
            let state = NSEntityDescription.insertNewObject(forEntityName: "ConversationListStateEntity", into: context)
            state.setValue(true, forKey: "isLoaded")
            state.setValue(42, forKey: "syncedChangeVersion")
        }

        let stored = try await ConversationStorageService(container: CoreDataStack.makeContainer(storeURL: storeURL)).fetchList()

        XCTAssertEqual(stored.conversations.map(\.conversationId), [7])
        XCTAssertEqual(stored.conversations.first?.lastMessage?.senderId, 0)
        XCTAssertEqual(stored.state.syncedChangeVersion, 42)
        XCTAssertTrue(stored.state.removedVersions.isEmpty)
        XCTAssertTrue(stored.state.pendingConversations.isEmpty)
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

    /// Вставляет переписку прежней версии модели — только поля, общие для всех версий.
    /// - Parameters:
    ///   - id: `conversationId`.
    ///   - context: контекст прежней версии модели.
    @discardableResult
    private func insertConversation(id: Int, into context: NSManagedObjectContext) throws -> NSManagedObject {
        let conversation = NSEntityDescription.insertNewObject(forEntityName: "ConversationEntity", into: context)
        conversation.setValue(id, forKey: "conversationId")
        conversation.setValue("group", forKey: "type")
        conversation.setValue(try JSONEncoder().encode([1, 2]), forKey: "memberIds")
        return conversation
    }

    /// Вставляет пользователя прежней версии модели.
    /// - Parameters:
    ///   - id: `userId`.
    ///   - context: контекст прежней версии модели.
    @discardableResult
    private func insertUser(id: Int, into context: NSManagedObjectContext) throws -> NSManagedObject {
        let user = NSEntityDescription.insertNewObject(forEntityName: "UserEntity", into: context)
        user.setValue(id, forKey: "userId")
        user.setValue("petr", forKey: "login")
        user.setValue("Petr", forKey: "name")
        return user
    }
}
