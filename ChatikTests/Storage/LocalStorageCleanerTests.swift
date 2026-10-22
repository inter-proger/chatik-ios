//
//  LocalStorageCleanerTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class LocalStorageCleanerTests: XCTestCase {
    /// Кейс: в БД сохранены переписки со вложенными пользователями и файлами, отдельные пользователь и файл,
    /// сообщения и прочтение другими участниками.
    /// Ожидание: после `clearAll()` все storage-сервисы возвращают пустые выборки, состояние синхронизации списка
    /// сброшено.
    func test_clearAll_removesAllEntities() async throws {
        let container = CoreDataStack.makeContainer(inMemory: true)
        let conversations = ConversationStorageService(container: container)
        let users = UserStorageService(container: container)
        let files = FileStorageService(container: container)
        let messages = MessageStorageService(container: container)
        let memberReads = MemberReadStorageService(container: container)
        try await memberReads.apply([1: MemberReadWrite(pointers: [2: 15], createsMissing: true)])
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
        let remainingMemberReads = try await memberReads.fetchConversationIds()
        XCTAssertTrue(remainingList.conversations.isEmpty)
        XCTAssertEqual(remainingList.state, ConversationListState())
        XCTAssertTrue(remainingUsers.isEmpty)
        XCTAssertTrue(remainingFiles.isEmpty)
        XCTAssertTrue(remainingMessages.isEmpty)
        XCTAssertNil(remainingCacheState)
        XCTAssertTrue(remainingMemberReads.isEmpty)
    }

    /// Кейс: в БД сохранены переписка, черновики и неотправленные сообщения двух пользователей.
    /// Ожидание: после `clearAll()` переписка удалена, а черновики и неотправленные сообщения обоих пользователей
    /// на месте.
    func test_clearAll_keepsMessageDraftsAndOutgoingMessages() async throws {
        let container = CoreDataStack.makeContainer(inMemory: true)
        let conversations = ConversationStorageService(container: container)
        let drafts = MessageDraftStorageService(container: container)
        let outgoing = OutgoingMessageStorageService(container: container)
        try await conversations.save(conversations: [.groupStub], state: ConversationListState(isLoaded: true))
        try await drafts.apply([7: .draft("Черновик первого")], userId: 1)
        try await drafts.apply([7: .draft("Черновик второго")], userId: 2)
        try await outgoing.save(message: .stub(clientId: "a", senderId: 1, status: .failed))
        try await outgoing.save(message: .stub(clientId: "a", senderId: 2, status: .failed))
        let sut = LocalStorageCleaner(container: container)

        try await sut.clearAll()

        let remainingList = try await conversations.fetchList()
        let firstDrafts = try await drafts.fetchAll(userId: 1).mapValues(\.text)
        let secondDrafts = try await drafts.fetchAll(userId: 2).mapValues(\.text)
        let firstOutgoing = try await outgoing.fetchAll(senderId: 1)
        let secondOutgoing = try await outgoing.fetchAll(senderId: 2)
        XCTAssertTrue(remainingList.conversations.isEmpty)
        XCTAssertEqual(firstDrafts, [7: "Черновик первого"])
        XCTAssertEqual(secondDrafts, [7: "Черновик второго"])
        XCTAssertEqual(firstOutgoing.map(\.clientId), ["a"])
        XCTAssertEqual(secondOutgoing.map(\.clientId), ["a"])
    }
}
