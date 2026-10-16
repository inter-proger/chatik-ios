//
//  MessageDraftServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageDraftServiceTests: XCTestCase {
    private var storage: MessageDraftStorageServiceMock!
    private var backgroundTasks: BackgroundTaskRunnerMock!
    private var sut: MessageDraftService!
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    override func setUp() async throws {
        try await super.setUp()
        storage = MessageDraftStorageServiceMock()
        backgroundTasks = BackgroundTaskRunnerMock()
        let now = now
        sut = MessageDraftService(storage: storage, backgroundTasks: backgroundTasks, now: { now })
    }

    override func tearDown() async throws {
        await waitForWrites()
        sut = nil
        backgroundTasks = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Загрузка

    /// Кейс: в БД черновики пользователя; вызвана загрузка.
    /// Ожидание: черновики доступны из памяти синхронно, у переписки без черновика его нет.
    func test_load_readsDraftsIntoMemory() async {
        storage.drafts = [1: [7: "Привет", 8: "Как дела?"]]

        await sut.load(userId: 1)

        XCTAssertEqual(sut.draft(for: 7), "Привет")
        XCTAssertTrue(sut.hasDraft(for: 8))
        XCTAssertNil(sut.draft(for: 9))
        XCTAssertFalse(sut.hasDraft(for: 9))
    }

    /// Кейс: вызвана загрузка черновиков.
    /// Ожидание: до чтения удалены черновики, не сохранявшиеся дольше `draftLifetime` от текущего времени.
    func test_load_deletesExpiredDraftsBeforeFetch() async {
        await sut.load(userId: 1)

        XCTAssertEqual(storage.deleteCutoffs, [now.addingTimeInterval(-MessageDraftService.draftLifetime)])
        XCTAssertEqual(storage.deleteCountsBeforeFetch, [1])
    }

    /// Кейс: удаление просроченных черновиков упало.
    /// Ожидание: загрузка не останавливается — черновики прочитаны.
    func test_load_deleteExpiredFails_stillLoadsDrafts() async {
        storage.drafts = [1: [7: "Черновик"]]
        storage.stubbedDeleteError = URLError(.unknown)

        await sut.load(userId: 1)

        XCTAssertEqual(sut.draft(for: 7), "Черновик")
    }

    /// Кейс: черновики пользователя уже загружены; загрузка вызвана повторно.
    /// Ожидание: БД повторно не читается.
    func test_load_sameUserTwice_readsStorageOnce() async {
        await sut.load(userId: 1)

        await sut.load(userId: 1)

        XCTAssertEqual(storage.fetchCallCount, 1)
    }

    /// Кейс: загружены черновики первого пользователя; затем загрузка для второго.
    /// Ожидание: в памяти только черновики второго — черновиков первого не видно.
    func test_load_otherUser_replacesMemory() async {
        storage.drafts = [1: [7: "От первого"], 2: [8: "От второго"]]
        await sut.load(userId: 1)

        await sut.load(userId: 2)

        XCTAssertNil(sut.draft(for: 7))
        XCTAssertEqual(sut.draft(for: 8), "От второго")
    }

    /// Кейс: черновик сохранён, запись в БД ещё идёт; пользователь вышел и сразу загружается снова.
    /// Ожидание: чтение начинается только после записи — загруженный черновик включает её.
    func test_load_waitsForPendingWrite() async {
        await sut.load(userId: 1)
        let gate = Gate()
        storage.nextApplyGate = gate
        sut.save(text: "Привет", conversationId: 7, userId: 1)
        await yieldUntil { gate.isWaiting }
        sut.prepareForLogout()

        let loading = Task { await sut.load(userId: 1) }
        await yieldTimes()
        XCTAssertEqual(storage.fetchCallCount, 1)
        gate.open()
        await loading.value

        XCTAssertEqual(sut.draft(for: 7), "Привет")
    }

    // MARK: - Изменения в памяти

    /// Кейс: черновики загружены; текст поля ввода меняется.
    /// Ожидание: черновик меняется в памяти, в БД ничего не пишется.
    func test_update_changesMemoryWithoutWriting() async {
        await sut.load(userId: 1)

        sut.update(text: "Прив", conversationId: 7, userId: 1)
        sut.update(text: "Привет", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(sut.draft(for: 7), "Привет")
        XCTAssertTrue(storage.applied.isEmpty)
        XCTAssertTrue(backgroundTasks.requestedNames.isEmpty)
    }

    /// Кейс: у переписки есть черновик; текст поля меняется на пустой или из одних пробельных и невидимых символов.
    /// Ожидание: черновик пропадает из памяти.
    func test_update_blankText_removesDraft() async {
        let texts = [
            "",
            "   ",
            "\n\t\n",
            "\u{200B}\u{FEFF}",
        ]

        for text in texts {
            storage.drafts = [1: [7: "Черновик"]]
            let now = now
        sut = MessageDraftService(storage: storage, backgroundTasks: backgroundTasks, now: { now })
            await sut.load(userId: 1)

            sut.update(text: text, conversationId: 7, userId: 1)

            XCTAssertNil(sut.draft(for: 7), text.debugDescription)
        }
    }

    /// Кейс: непустой текст с пробелами и переводами строк по краям.
    /// Ожидание: черновик хранится как есть, без обрезки.
    func test_update_keepsTextAsIs() async {
        await sut.load(userId: 1)

        sut.update(text: "  Привет\n", conversationId: 7, userId: 1)

        XCTAssertEqual(sut.draft(for: 7), "  Привет\n")
    }

    /// Кейс: загрузки для пользователя не было (или она была для другого); экран меняет и сохраняет черновик.
    /// Ожидание: `update`, `save` и `remove` ничего не делают — ни в памяти, ни в БД.
    func test_changes_userWithoutLoad_areIgnored() async {
        sut.update(text: "Текст", conversationId: 7, userId: 1)
        sut.save(text: "Текст", conversationId: 7, userId: 1)
        await sut.load(userId: 2)
        sut.update(text: "Чужой", conversationId: 8, userId: 1)
        sut.save(text: "Чужой", conversationId: 8, userId: 1)
        sut.remove(conversationId: 8, userId: 1)

        await waitForWrites()
        XCTAssertNil(sut.draft(for: 7))
        XCTAssertNil(sut.draft(for: 8))
        XCTAssertTrue(storage.applied.isEmpty)
    }

    // MARK: - Запись в БД

    /// Кейс: текст двух переписок изменён в памяти; затем сохранение третьей.
    /// Ожидание: в БД одной пачкой записаны все три изменения.
    func test_save_writesAllDirtyConversationsInOneBatch() async {
        storage.drafts = [1: [9: "Старый"]]
        await sut.load(userId: 1)
        sut.update(text: "Первый", conversationId: 7, userId: 1)
        sut.update(text: "", conversationId: 9, userId: 1)

        sut.save(text: "Второй", conversationId: 8, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.applied.count, 1)
        XCTAssertEqual(storage.applied.first?.changes, [7: .save("Первый"), 8: .save("Второй"), 9: .delete])
        XCTAssertEqual(storage.applied.first?.userId, 1)
        XCTAssertEqual(storage.drafts[1], [7: "Первый", 8: "Второй"])
    }

    /// Кейс: черновик загружен; экран уходит, не изменив текст (в том числе повторно), или поле было пустым.
    /// Ожидание: в БД ничего не пишется.
    func test_save_withoutChanges_doesNotWrite() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)

        sut.save(text: "Черновик", conversationId: 7, userId: 1)
        sut.save(text: "Черновик", conversationId: 7, userId: 1)
        sut.save(text: "", conversationId: 8, userId: 1)

        await waitForWrites()
        XCTAssertTrue(storage.applied.isEmpty)
    }

    /// Кейс: первая запись задержана; за это время сохранён новый текст.
    /// Ожидание: вторая запись ждёт первую — в БД последней записывается последняя версия.
    func test_save_writesInCallOrder() async {
        await sut.load(userId: 1)
        let gate = Gate()
        storage.nextApplyGate = gate
        sut.save(text: "Первый", conversationId: 7, userId: 1)
        await yieldUntil { gate.isWaiting }

        sut.save(text: "Второй", conversationId: 7, userId: 1)
        await yieldTimes()
        XCTAssertEqual(storage.applied.count, 1)
        gate.open()

        await waitForWrites()
        XCTAssertEqual(storage.applied.map(\.changes), [[7: .save("Первый")], [7: .save("Второй")]])
        XCTAssertEqual(storage.drafts[1], [7: "Второй"])
    }

    /// Кейс: у переписки черновик; сообщение отправлено.
    /// Ожидание: черновик удалён из памяти и из БД.
    func test_remove_deletesFromMemoryAndStorage() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)

        sut.remove(conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertNil(sut.draft(for: 7))
        XCTAssertEqual(storage.drafts[1], [:])
    }

    /// Кейс: черновик сохраняется.
    /// Ожидание: фоновая задача запрошена синхронно, ещё до запуска записи, и запись идёт внутри неё.
    func test_save_requestsBackgroundTaskSynchronously() async {
        await sut.load(userId: 1)

        sut.save(text: "Текст", conversationId: 7, userId: 1)

        XCTAssertEqual(backgroundTasks.requestedNames.count, 1)
        XCTAssertTrue(storage.applied.isEmpty)
        await waitForWrites()
        XCTAssertEqual(storage.applied.count, 1)
    }

    /// Кейс: запись черновика не удалась; затем сохранена другая переписка.
    /// Ожидание: неудавшаяся переписка уходит в БД со следующей пачкой; текст в памяти не откатывается.
    func test_save_afterFailedWrite_retriesWithNextBatch() async {
        await sut.load(userId: 1)
        storage.stubbedApplyError = URLError(.unknown)
        sut.save(text: "Первый", conversationId: 7, userId: 1)
        await waitForWrites()
        XCTAssertEqual(sut.draft(for: 7), "Первый")
        storage.stubbedApplyError = nil

        sut.save(text: "Второй", conversationId: 8, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.applied.last?.changes, [7: .save("Первый"), 8: .save("Второй")])
        XCTAssertEqual(storage.drafts[1], [7: "Первый", 8: "Второй"])
    }

    /// Кейс: запись черновика не удалась; экран уходит повторно с тем же текстом.
    /// Ожидание: переписка помечена незаписанной — тот же текст записывается снова.
    func test_save_sameTextAfterFailedWrite_writesAgain() async {
        await sut.load(userId: 1)
        storage.stubbedApplyError = URLError(.unknown)
        sut.save(text: "Текст", conversationId: 7, userId: 1)
        await waitForWrites()
        storage.stubbedApplyError = nil

        sut.save(text: "Текст", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.applied.count, 2)
        XCTAssertEqual(storage.drafts[1], [7: "Текст"])
    }

    /// Кейс: запись черновика идёт; за это время текст изменён в памяти; запись удалась.
    /// Ожидание: переписка остаётся незаписанной — следующее сохранение того же текста пишет его в БД.
    func test_save_textChangedDuringWrite_staysDirty() async {
        await sut.load(userId: 1)
        let gate = Gate()
        storage.nextApplyGate = gate
        sut.save(text: "Первый", conversationId: 7, userId: 1)
        await yieldUntil { gate.isWaiting }
        sut.update(text: "Второй", conversationId: 7, userId: 1)
        gate.open()
        await waitForWrites()

        sut.save(text: "Второй", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.drafts[1], [7: "Второй"])
    }

    // MARK: - Неудачная загрузка

    /// Кейс: чтение черновиков упало; экран сохраняет непустой текст переписки, у которой в БД есть черновик.
    /// Ожидание: текст виден в памяти и записан в БД поверх старого.
    func test_save_afterFailedLoad_writesNonEmptyText() async {
        storage.drafts = [1: [7: "Старый"]]
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)
        XCTAssertNil(sut.draft(for: 7))

        sut.save(text: "Новый", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(sut.draft(for: 7), "Новый")
        XCTAssertEqual(storage.drafts[1], [7: "Новый"])
    }

    /// Кейс: чтение черновиков упало; экран уходит с пустым полем или черновик удаляется после отправки.
    /// Ожидание: черновики в БД не удаляются — поле было пустым, потому что черновик не загрузился.
    func test_emptyChanges_afterFailedLoad_keepUnseenDrafts() async {
        storage.drafts = [1: [7: "Невиденный", 8: "Ещё один"]]
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)

        sut.save(text: "", conversationId: 7, userId: 1)
        sut.remove(conversationId: 8, userId: 1)

        await waitForWrites()
        XCTAssertTrue(storage.applied.isEmpty)
        XCTAssertEqual(storage.drafts[1], [7: "Невиденный", 8: "Ещё один"])
    }

    /// Кейс: чтение черновиков упало; пользователь набрал текст и сохранил, затем стёр и сохранил пустой.
    /// Ожидание: черновик, набранный в этой сессии, удаляется и из памяти, и из БД.
    func test_emptySave_afterNonEmptyInFailedLoad_deletes() async {
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)
        sut.save(text: "Текст", conversationId: 7, userId: 1)
        await waitForWrites()

        sut.save(text: "", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertNil(sut.draft(for: 7))
        XCTAssertEqual(storage.drafts[1], [:])
    }

    // MARK: - Выход из аккаунта

    /// Кейс: текст изменён в памяти, но не сохранён; начинается выход из аккаунта (через наблюдателя выхода).
    /// Ожидание: память очищена, незаписанный текст записан в БД, остальные черновики в БД на месте.
    func test_logout_writesDirtyDraftsAndClearsMemory() async {
        storage.drafts = [1: [8: "Сохранённый"]]
        await sut.load(userId: 1)
        sut.update(text: "Несохранённый", conversationId: 7, userId: 1)
        let observer = MessageDraftLogoutObserver(draftService: sut)

        await observer.authServiceWillLogout()

        await waitForWrites()
        XCTAssertNil(sut.draft(for: 7))
        XCTAssertNil(sut.draft(for: 8))
        XCTAssertEqual(storage.drafts[1], [7: "Несохранённый", 8: "Сохранённый"])
    }

    /// Кейс: пользователь вышел, экран переписки уходит после выхода и сохраняет текст; другой пользователь тоже
    /// пытается сохранить; затем вышедший входит снова.
    /// Ожидание: текст вышедшего записан только в БД (память пуста, `update` ничего не делает), чужое сохранение
    /// игнорируется; после повторного входа черновик вышедшего снова в памяти.
    func test_save_afterLogout_writesOnlyToStorage() async {
        await sut.load(userId: 1)
        sut.prepareForLogout()

        sut.update(text: "Набрано после выхода", conversationId: 7, userId: 1)
        XCTAssertNil(sut.draft(for: 7))
        sut.save(text: "Набрано после выхода", conversationId: 7, userId: 1)
        sut.save(text: "Чужой", conversationId: 8, userId: 2)
        await waitForWrites()
        XCTAssertNil(sut.draft(for: 7))
        XCTAssertEqual(storage.drafts, [1: [7: "Набрано после выхода"]])

        await sut.load(userId: 1)

        XCTAssertEqual(sut.draft(for: 7), "Набрано после выхода")
    }

    /// Кейс: пользователь вышел, экран уходит после выхода с пустым полем, хотя у переписки был черновик.
    /// Ожидание: черновик удалён из БД — пользователь видел его и стёр.
    func test_emptySave_afterLogout_deletesFromStorage() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)
        sut.prepareForLogout()

        sut.save(text: "", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.drafts[1], [:])
    }

    /// Кейс: чтение черновиков упало; пользователь вышел, экран уходит после выхода с пустым полем.
    /// Ожидание: черновик в БД не удаляется — поле было пустым, потому что черновик не загрузился.
    func test_emptySave_afterLogoutWithFailedLoad_keepsUnseenDraft() async {
        storage.drafts = [1: [7: "Невиденный"]]
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)
        sut.prepareForLogout()

        sut.save(text: "", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertTrue(storage.applied.isEmpty)
        XCTAssertEqual(storage.drafts[1], [7: "Невиденный"])
    }

    /// Кейс: чтение черновиков упало; пользователь вышел, экран после выхода сохраняет текст, затем пустое поле.
    /// Ожидание: черновик, записанный после выхода, удаляется.
    func test_emptySave_afterNonEmptySaveAfterLogout_deletes() async {
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)
        sut.prepareForLogout()
        sut.save(text: "Текст", conversationId: 7, userId: 1)
        await waitForWrites()

        sut.save(text: "", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.drafts[1], [:])
    }

    // MARK: - Helpers

    /// Ждёт, пока закончатся все записи в БД, запущенные сервисом.
    private func waitForWrites() async {
        await waitUntil { [unowned self] in backgroundTasks.runningCount == 0 }
    }
}
