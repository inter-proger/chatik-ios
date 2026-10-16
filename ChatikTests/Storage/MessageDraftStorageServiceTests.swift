//
//  MessageDraftStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class MessageDraftStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: MessageDraftStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = MessageDraftStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: черновик переписки сохранён, затем сохранён повторно с новым текстом.
    /// Ожидание: в БД одна запись с новым текстом.
    func test_apply_existingDraft_updatesRecord() async throws {
        try await sut.apply([7: .save("Привет")], userId: 1)

        try await sut.apply([7: .save("Привет, как дела?")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1)
        let count = try await container.performRead { context in
            try context.count(for: NSFetchRequest<MessageDraftEntity>(entityName: MessageDraftEntity.entityName))
        }
        XCTAssertEqual(drafts, [7: "Привет, как дела?"])
        XCTAssertEqual(count, 1)
    }

    /// Кейс: в БД черновики двух переписок; одной пачкой одна удаляется, другая обновляется, третья добавляется.
    /// Ожидание: все изменения пачки применены.
    func test_apply_saveAndDeleteInOneBatch_appliesAll() async throws {
        try await sut.apply([1: .save("Первый"), 2: .save("Второй")], userId: 1)

        try await sut.apply([1: .delete, 2: .save("Второй, исправленный"), 3: .save("Третий")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(drafts, [2: "Второй, исправленный", 3: "Третий"])
    }

    /// Кейс: удаление черновика, которого нет в БД.
    /// Ожидание: ошибки нет, остальные черновики на месте.
    func test_apply_deleteMissingDraft_doesNotThrow() async throws {
        try await sut.apply([1: .save("Текст")], userId: 1)

        try await sut.apply([2: .delete], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(drafts, [1: "Текст"])
    }

    /// Кейс: у двух пользователей черновики одной и той же переписки; второй удаляет свой.
    /// Ожидание: каждый пользователь видит только свои черновики, удаление не трогает чужой.
    func test_fetchAll_returnsOnlyDraftsOfUser() async throws {
        try await sut.apply([7: .save("От первого"), 8: .save("Ещё от первого")], userId: 1)
        try await sut.apply([7: .save("От второго")], userId: 2)

        try await sut.apply([7: .delete], userId: 2)

        let first = try await sut.fetchAll(userId: 1)
        let second = try await sut.fetchAll(userId: 2)
        XCTAssertEqual(first, [7: "От первого", 8: "Ещё от первого"])
        XCTAssertEqual(second, [:])
    }

    /// Кейс: черновик из одних пробелов и переводов строк сохранён хранилищу напрямую.
    /// Ожидание: хранилище не обрезает и не отбрасывает текст — пустоту решает сервис черновиков.
    func test_apply_keepsTextAsIs() async throws {
        try await sut.apply([1: .save("  Текст\n\n")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(drafts, [1: "  Текст\n\n"])
    }

    /// Кейс: у двух пользователей черновики, сохранённые до и после границы, и черновик ровно на границе;
    /// удаляются черновики старше границы.
    /// Ожидание: удалены только сохранённые раньше границы — у обоих пользователей; остальные на месте.
    func test_deleteAll_updatedBefore_deletesOnlyOlderDraftsOfAllUsers() async throws {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        try await makeStorage(now: cutoff.addingTimeInterval(-1)).apply([1: .save("Старый первого")], userId: 1)
        try await makeStorage(now: cutoff.addingTimeInterval(-1)).apply([2: .save("Старый второго")], userId: 2)
        try await makeStorage(now: cutoff).apply([3: .save("На границе")], userId: 1)
        try await makeStorage(now: cutoff.addingTimeInterval(1)).apply([4: .save("Новый")], userId: 2)

        try await sut.deleteAll(updatedBefore: cutoff)

        let first = try await sut.fetchAll(userId: 1)
        let second = try await sut.fetchAll(userId: 2)
        XCTAssertEqual(first, [3: "На границе"])
        XCTAssertEqual(second, [4: "Новый"])
    }

    /// Кейс: старый черновик сохранён повторно; затем удаляются черновики старше первого сохранения.
    /// Ожидание: черновик на месте — срок отсчитывается от последнего сохранения.
    func test_deleteAll_resavedDraft_isKept() async throws {
        let firstSave = Date(timeIntervalSince1970: 1_000_000)
        try await makeStorage(now: firstSave).apply([1: .save("Текст")], userId: 1)
        try await makeStorage(now: firstSave.addingTimeInterval(100)).apply([1: .save("Текст, дописанный")], userId: 1)

        try await sut.deleteAll(updatedBefore: firstSave.addingTimeInterval(50))

        let drafts = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(drafts, [1: "Текст, дописанный"])
    }

    // MARK: - Helpers

    /// Хранилище над той же БД с подменённым временем сохранения.
    /// - Parameter now: время, которое получит `updatedAt` записанных черновиков.
    private func makeStorage(now: Date) -> MessageDraftStorageService {
        MessageDraftStorageService(container: container, now: { now })
    }
}
