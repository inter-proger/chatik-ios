//
//  MemberReadStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class MemberReadStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: MemberReadStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = MemberReadStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: указатель участника сохранён, затем сохранён больший и меньший.
    /// Ожидание: одна запись с наибольшим указателем — меньший не откатывает прочтение.
    func test_apply_existingPointer_keepsMaximum() async throws {
        try await sut.apply([7: MemberReadWrite(pointers: [2: 10], createsMissing: true)])

        try await sut.apply([7: MemberReadWrite(pointers: [2: 15], createsMissing: true)])
        try await sut.apply([7: MemberReadWrite(pointers: [2: 12], createsMissing: true)])

        let pointers = try await sut.fetchPointers(conversationId: 7)
        let count = try await container.performRead { context in
            try context.count(for: NSFetchRequest<MemberReadEntity>(entityName: MemberReadEntity.entityName))
        }
        XCTAssertEqual(pointers, [2: 15])
        XCTAssertEqual(count, 1)
    }

    /// Кейс: у переписки сохранены указатели участников 2 и 3; приходит ответ с составом из 2 и 4.
    /// Ожидание: указатель 3 удалён, 2 обновлён, 4 добавлен.
    func test_apply_members_removesMissingMembers() async throws {
        try await sut.apply([7: MemberReadWrite(pointers: [2: 10, 3: 10], createsMissing: true)])

        try await sut.apply([7: MemberReadWrite(pointers: [2: 12, 4: 5], members: [2, 4], createsMissing: true)])

        let pointers = try await sut.fetchPointers(conversationId: 7)
        XCTAssertEqual(pointers, [2: 12, 4: 5])
    }

    /// Кейс: изменение без `createsMissing` для переписки без меты и для переписки с метой.
    /// Ожидание: первой мета не создаётся, вторая обновляется.
    func test_apply_withoutCreatesMissing_updatesOnlyStoredConversations() async throws {
        try await sut.apply([8: MemberReadWrite(pointers: [2: 1], createsMissing: true)])

        try await sut.apply([
            7: MemberReadWrite(pointers: [2: 10], createsMissing: false),
            8: MemberReadWrite(pointers: [3: 4], createsMissing: false),
        ])

        let missing = try await sut.fetchPointers(conversationId: 7)
        let stored = try await sut.fetchPointers(conversationId: 8)
        XCTAssertNil(missing)
        XCTAssertEqual(stored, [2: 1, 3: 4])
    }

    /// Кейс: мета сохранена у двух переписок, у одной из них несколько участников.
    /// Ожидание: каждая переписка в списке один раз; указатели читаются по своей переписке.
    func test_fetchConversationIds_returnsDistinctConversations() async throws {
        try await sut.apply([
            7: MemberReadWrite(pointers: [2: 10, 3: 11], createsMissing: true),
            8: MemberReadWrite(pointers: [2: 1], createsMissing: true),
        ])

        let ids = try await sut.fetchConversationIds()
        let pointers = try await sut.fetchPointers(conversationId: 7)

        XCTAssertEqual(ids, [7, 8])
        XCTAssertEqual(pointers, [2: 10, 3: 11])
    }

    /// Кейс: чтение меты переписки, которой нет в БД.
    /// Ожидание: `nil` — меты нет, ошибки нет.
    func test_fetchPointers_missingConversation_returnsNil() async throws {
        let pointers = try await sut.fetchPointers(conversationId: 1)

        XCTAssertNil(pointers)
    }

    // MARK: - Склейка изменений

    /// Кейс: два изменения из событий одной переписки.
    /// Ожидание: указатели слиты по максимуму, состав не задан, мета создаётся, если создавало хоть одно.
    func test_merge_events_keepsMaximum() {
        var sut = MemberReadWrite(pointers: [2: 10, 3: 5], createsMissing: false)

        sut.merge(MemberReadWrite(pointers: [2: 8, 4: 1], createsMissing: true))

        XCTAssertEqual(sut, MemberReadWrite(pointers: [2: 10, 3: 5, 4: 1], createsMissing: true))
    }

    /// Кейс: после события участника 3 пришёл ответ с составом без него.
    /// Ожидание: указатель 3 отброшен, состав — из ответа.
    func test_merge_newerMembers_dropsRemovedMembers() {
        var sut = MemberReadWrite(pointers: [2: 10, 3: 5], createsMissing: true)

        sut.merge(MemberReadWrite(pointers: [2: 9], members: [2], createsMissing: true))

        XCTAssertEqual(sut, MemberReadWrite(pointers: [2: 10], members: [2], createsMissing: true))
    }

    /// Кейс: после ответа с составом из участника 2 пришло событие нового участника 3.
    /// Ожидание: участник 3 добавлен в состав — запись не удалит его указатель.
    func test_merge_eventAfterMembers_addsMember() {
        var sut = MemberReadWrite(pointers: [2: 10], members: [2], createsMissing: true)

        sut.merge(MemberReadWrite(pointers: [3: 4], createsMissing: true))

        XCTAssertEqual(sut, MemberReadWrite(pointers: [2: 10, 3: 4], members: [2, 3], createsMissing: true))
    }
}
