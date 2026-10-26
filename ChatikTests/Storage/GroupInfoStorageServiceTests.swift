//
//  GroupInfoStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class GroupInfoStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: GroupInfoStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = GroupInfoStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: состав сохранён и прочитан.
    /// Ожидание: состав восстановлен без изменений; группа есть в списке сохранённых.
    func test_save_roundTrips() async throws {
        let info = makeInfo(version: 2)

        try await sut.save(info, createsMissing: true)

        let stored = try await sut.fetch(conversationId: 12)
        let ids = try await sut.fetchConversationIds()
        XCTAssertEqual(stored, info)
        XCTAssertEqual(ids, [12])
    }

    /// Кейс: сохранена версия 3, затем — версия 2.
    /// Ожидание: остаётся версия 3, запись одна.
    func test_save_olderVersion_keepsNewer() async throws {
        try await sut.save(makeInfo(version: 3), createsMissing: true)

        try await sut.save(makeInfo(version: 2), createsMissing: true)

        let stored = try await sut.fetch(conversationId: 12)
        let count = try await container.performRead { context in
            try context.count(for: NSFetchRequest<GroupInfoEntity>(entityName: GroupInfoEntity.entityName))
        }
        XCTAssertEqual(stored?.version, 3)
        XCTAssertEqual(count, 1)
    }

    /// Кейс: запись без `createsMissing` для группы без сохранённого состава.
    /// Ожидание: запись не создана.
    func test_save_withoutCreatesMissing_skipsMissing() async throws {
        try await sut.save(makeInfo(version: 1), createsMissing: false)

        let stored = try await sut.fetch(conversationId: 12)
        XCTAssertNil(stored)
    }

    /// Кейс: состав удалён; затем удалён ещё раз.
    /// Ожидание: состава нет, повторное удаление не падает.
    func test_delete_removesAndToleratesMissing() async throws {
        try await sut.save(makeInfo(version: 1), createsMissing: true)

        try await sut.delete(conversationId: 12)
        try await sut.delete(conversationId: 12)

        let stored = try await sut.fetch(conversationId: 12)
        XCTAssertNil(stored)
    }

    /// Состав группы 12: владелец и участник.
    /// - Parameter version: версия состава.
    private func makeInfo(version: Int) -> GroupInfo {
        GroupInfo(conversationId: 12, version: version, members: [
            GroupMember(userId: 1, role: .owner, joinedAfterMessageId: 0),
            GroupMember(userId: 2, role: .member, joinedAfterMessageId: 318),
        ])
    }
}
