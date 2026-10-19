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
        try await sut.apply([7: .draft("Привет")], userId: 1)

        try await sut.apply([7: .draft("Привет, как дела?")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1).mapValues(\.text)
        let count = try await container.performRead { context in
            try context.count(for: NSFetchRequest<MessageDraftEntity>(entityName: MessageDraftEntity.entityName))
        }
        XCTAssertEqual(drafts, [7: "Привет, как дела?"])
        XCTAssertEqual(count, 1)
    }

    /// Кейс: в БД черновики двух переписок; одной пачкой одна удаляется, другая обновляется, третья добавляется.
    /// Ожидание: все изменения пачки применены.
    func test_apply_saveAndDeleteInOneBatch_appliesAll() async throws {
        try await sut.apply([1: .draft("Первый"), 2: .draft("Второй")], userId: 1)

        try await sut.apply([1: .draft(nil), 2: .draft("Второй, исправленный"), 3: .draft("Третий")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1).mapValues(\.text)
        XCTAssertEqual(drafts, [2: "Второй, исправленный", 3: "Третий"])
    }

    /// Кейс: удаление черновика, которого нет в БД.
    /// Ожидание: ошибки нет, остальные черновики на месте.
    func test_apply_deleteMissingDraft_doesNotThrow() async throws {
        try await sut.apply([1: .draft("Текст")], userId: 1)

        try await sut.apply([2: .draft(nil)], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1).mapValues(\.text)
        XCTAssertEqual(drafts, [1: "Текст"])
    }

    /// Кейс: у двух пользователей черновики одной и той же переписки; второй удаляет свой.
    /// Ожидание: каждый пользователь видит только свои черновики, удаление не трогает чужой.
    func test_fetchAll_returnsOnlyDraftsOfUser() async throws {
        try await sut.apply([7: .draft("От первого"), 8: .draft("Ещё от первого")], userId: 1)
        try await sut.apply([7: .draft("От второго")], userId: 2)

        try await sut.apply([7: .draft(nil)], userId: 2)

        let first = try await sut.fetchAll(userId: 1).mapValues(\.text)
        let second = try await sut.fetchAll(userId: 2).mapValues(\.text)
        XCTAssertEqual(first, [7: "От первого", 8: "Ещё от первого"])
        XCTAssertEqual(second, [:])
    }

    /// Кейс: черновик из одних пробелов и переводов строк сохранён хранилищу напрямую.
    /// Ожидание: хранилище не обрезает и не отбрасывает текст — пустоту решает сервис черновиков.
    func test_apply_keepsTextAsIs() async throws {
        try await sut.apply([1: .draft("  Текст\n\n")], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1).mapValues(\.text)
        XCTAssertEqual(drafts, [1: "  Текст\n\n"])
    }

    /// Кейс: у двух пользователей черновики, сохранённые до и после границы, и черновик ровно на границе;
    /// удаляются черновики старше границы.
    /// Ожидание: удалены только сохранённые раньше границы — у обоих пользователей; остальные на месте.
    func test_deleteAll_updatedBefore_deletesOnlyOlderDraftsOfAllUsers() async throws {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        try await makeStorage(now: cutoff.addingTimeInterval(-1)).apply([1: .draft("Старый первого")], userId: 1)
        try await makeStorage(now: cutoff.addingTimeInterval(-1)).apply([2: .draft("Старый второго")], userId: 2)
        try await makeStorage(now: cutoff).apply([3: .draft("На границе")], userId: 1)
        try await makeStorage(now: cutoff.addingTimeInterval(1)).apply([4: .draft("Новый")], userId: 2)

        try await sut.deleteAll(updatedBefore: cutoff)

        let first = try await sut.fetchAll(userId: 1).mapValues(\.text)
        let second = try await sut.fetchAll(userId: 2).mapValues(\.text)
        XCTAssertEqual(first, [3: "На границе"])
        XCTAssertEqual(second, [4: "Новый"])
    }

    /// Кейс: старый черновик сохранён повторно; затем удаляются черновики старше первого сохранения.
    /// Ожидание: черновик на месте — срок отсчитывается от последнего сохранения.
    func test_deleteAll_resavedDraft_isKept() async throws {
        let firstSave = Date(timeIntervalSince1970: 1_000_000)
        try await makeStorage(now: firstSave).apply([1: .draft("Текст")], userId: 1)
        try await makeStorage(now: firstSave.addingTimeInterval(100)).apply([1: .draft("Текст, дописанный")], userId: 1)

        try await sut.deleteAll(updatedBefore: firstSave.addingTimeInterval(50))

        let drafts = try await sut.fetchAll(userId: 1).mapValues(\.text)
        XCTAssertEqual(drafts, [1: "Текст, дописанный"])
    }

    // MARK: - Правки

    /// Кейс: в одной переписке записаны черновик и правка, в другой — только правка.
    /// Ожидание: обе записи читаются целиком: черновик рядом с правкой и правка без черновика.
    func test_apply_edit_readsBackWithAndWithoutDraft() async throws {
        let first = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")
        let second = MessageEditDraft(messageId: 16, originalText: "Пока", text: "")

        try await sut.apply([7: MessageDraftChange(text: .some("Черновик"), edit: .some(first)), 8: .edit(second)], userId: 1)

        let drafts = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(drafts, [7: MessageDraft(text: "Черновик", edit: first), 8: MessageDraft(edit: second)])
    }

    /// Кейс: в записи черновик и правка; затем отдельно меняется правка, а потом отдельно — черновик.
    /// Ожидание: каждое изменение трогает только своё поле — правка не стирает черновик, и наоборот.
    func test_apply_partialChanges_keepOtherField() async throws {
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")
        let changedEdit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем!")
        try await sut.apply([7: MessageDraftChange(text: .some("Черновик"), edit: .some(edit))], userId: 1)

        try await sut.apply([7: .edit(changedEdit)], userId: 1)
        let afterEdit = try await sut.fetchAll(userId: 1)
        try await sut.apply([7: .draft("Новый черновик")], userId: 1)

        let afterDraft = try await sut.fetchAll(userId: 1)
        XCTAssertEqual(afterEdit[7], MessageDraft(text: "Черновик", edit: changedEdit))
        XCTAssertEqual(afterDraft[7], MessageDraft(text: "Новый черновик", edit: changedEdit))
    }

    /// Кейс: в записи черновик и правка; выключается правка, затем удаляется черновик.
    /// Ожидание: после выключения правки черновик на месте; после удаления черновика запись удалена из БД.
    func test_apply_clearingBothFields_deletesRecord() async throws {
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")
        try await sut.apply([7: MessageDraftChange(text: .some("Черновик"), edit: .some(edit))], userId: 1)

        try await sut.apply([7: .edit(nil)], userId: 1)
        let afterEdit = try await sut.fetchAll(userId: 1)
        try await sut.apply([7: .draft(nil)], userId: 1)

        let count = try await recordCount()
        XCTAssertEqual(afterEdit, [7: MessageDraft(text: "Черновик")])
        XCTAssertEqual(count, 0)
    }

    /// Кейс: для переписки без записи приходит изменение, которое только удаляет (выключить правку).
    /// Ожидание: запись не создаётся.
    func test_apply_clearingMissingRecord_doesNotCreateRecord() async throws {
        try await sut.apply([7: .edit(nil)], userId: 1)

        let count = try await recordCount()
        XCTAssertEqual(count, 0)
    }

    /// Кейс: в записи черновик и повреждённая правка — `editMessageId` есть, а текста правки нет.
    /// Ожидание: запись читается с черновиком и без правки.
    func test_fetchAll_corruptedEdit_readsWithoutEdit() async throws {
        try await container.performWrite { context in
            let entity = MessageDraftEntity(context: context)
            entity.userId = 1
            entity.conversationId = 7
            entity.text = "Черновик"
            entity.editMessageId = 15
            entity.editOriginalText = "Привет"
            try context.save()
        }

        let drafts = try await sut.fetchAll(userId: 1)

        XCTAssertEqual(drafts, [7: MessageDraft(text: "Черновик")])
    }

    // MARK: - Helpers

    /// Число записей черновиков в БД у всех пользователей.
    private func recordCount() async throws -> Int {
        try await container.performRead { context in
            try context.count(for: NSFetchRequest<MessageDraftEntity>(entityName: MessageDraftEntity.entityName))
        }
    }

    /// Хранилище над той же БД с подменённым временем сохранения.
    /// - Parameter now: время, которое получит `updatedAt` записанных черновиков.
    private func makeStorage(now: Date) -> MessageDraftStorageService {
        MessageDraftStorageService(container: container, now: { now })
    }
}
