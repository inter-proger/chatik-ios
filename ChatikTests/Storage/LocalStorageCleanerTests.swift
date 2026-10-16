//
//  LocalStorageCleanerTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class LocalStorageCleanerTests: XCTestCase {
    /// Кейс: в БД сохранены переписки со вложенными пользователями и файлами, отдельные пользователь и файл,
    /// а также сообщения.
    /// Ожидание: после `clearAll()` все storage-сервисы возвращают пустые выборки, состояние синхронизации списка
    /// сброшено.
    func test_clearAll_removesAllEntities() async throws {
        let container = CoreDataStack.makeContainer(inMemory: true)
        let conversations = ConversationStorageService(container: container)
        let users = UserStorageService(container: container)
        let files = FileStorageService(container: container)
        let messages = MessageStorageService(container: container)
        try await conversations.save(conversations: [.singleStub, .groupStub], state: ConversationListState(isLoaded: true))
        try await users.save(user: .stub)
        try await files.save(file: .stub)
        let cacheState = MessageCacheState(syncMark: .stub, nextBlockId: nil, hasMorePages: false)
        _ = try await messages.write(MessageStorageChanges(
            upserts: [.stub],
            stateChanges: [MessageCacheStateChange(conversationId: Message.stub.conversationId, kind: .replace(cacheState))]
        ))
        let sut = LocalStorageCleaner(container: container)

        try await sut.clearAll()

        let remainingList = try await conversations.fetchList()
        let remainingUsers = try await users.fetchAll()
        let remainingFiles = try await files.fetchAll()
        let remainingMessages = try await messages.fetchLatestBlocks(conversationId: Message.stub.conversationId, minCount: 10)
        let remainingCacheState = try await messages.fetchState(conversationId: Message.stub.conversationId)
        XCTAssertTrue(remainingList.conversations.isEmpty)
        XCTAssertEqual(remainingList.state, ConversationListState())
        XCTAssertTrue(remainingUsers.isEmpty)
        XCTAssertTrue(remainingFiles.isEmpty)
        XCTAssertTrue(remainingMessages.isEmpty)
        XCTAssertNil(remainingCacheState)
    }

    /// Кейс: в БД сохранены переписка и черновики двух пользователей.
    /// Ожидание: после `clearAll()` переписка удалена, а черновики обоих пользователей на месте.
    func test_clearAll_keepsMessageDrafts() async throws {
        let container = CoreDataStack.makeContainer(inMemory: true)
        let conversations = ConversationStorageService(container: container)
        let drafts = MessageDraftStorageService(container: container)
        try await conversations.save(conversations: [.groupStub], state: ConversationListState(isLoaded: true))
        try await drafts.apply([7: .save("Черновик первого")], userId: 1)
        try await drafts.apply([7: .save("Черновик второго")], userId: 2)
        let sut = LocalStorageCleaner(container: container)

        try await sut.clearAll()

        let remainingList = try await conversations.fetchList()
        let firstDrafts = try await drafts.fetchAll(userId: 1)
        let secondDrafts = try await drafts.fetchAll(userId: 2)
        XCTAssertTrue(remainingList.conversations.isEmpty)
        XCTAssertEqual(firstDrafts, [7: "Черновик первого"])
        XCTAssertEqual(secondDrafts, [7: "Черновик второго"])
    }
}
