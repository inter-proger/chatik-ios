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
    /// Ожидание: после `clearAll()` все storage-сервисы возвращают пустые выборки.
    func test_clearAll_removesAllEntities() async throws {
        let container = CoreDataStack.makeContainer(inMemory: true)
        let conversations = ConversationStorageService(container: container)
        let users = UserStorageService(container: container)
        let files = FileStorageService(container: container)
        let messages = MessageStorageService(container: container)
        try await conversations.save(conversations: [.singleStub, .groupStub])
        try await users.save(user: .stub)
        try await files.save(file: .stub)
        try await messages.save(message: .stub)
        let sut = LocalStorageCleaner(container: container)

        try await sut.clearAll()

        let remainingConversations = try await conversations.fetchAll()
        let remainingUsers = try await users.fetchAll()
        let remainingFiles = try await files.fetchAll()
        let remainingMessages = try await messages.fetchLatest(conversationId: Message.stub.conversationId, limit: 10)
        XCTAssertTrue(remainingConversations.isEmpty)
        XCTAssertTrue(remainingUsers.isEmpty)
        XCTAssertTrue(remainingFiles.isEmpty)
        XCTAssertTrue(remainingMessages.isEmpty)
    }
}
