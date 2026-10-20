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
        XCTAssertEqual(storage.applied.first?.changes, [7: .draft("Первый"), 8: .draft("Второй"), 9: .draft(nil)])
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
        XCTAssertEqual(storage.applied.map(\.changes), [[7: .draft("Первый")], [7: .draft("Второй")]])
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
        XCTAssertEqual(storage.applied.last?.changes, [7: .draft("Первый"), 8: .draft("Второй")])
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

    // MARK: - Редактирование

    /// Кейс: у переписки черновик; включается редактирование сообщения.
    /// Ожидание: правка с исходным текстом видна из памяти и сразу записана в БД, черновик не изменился.
    func test_beginEditing_keepsDraftAndWritesEdit() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)

        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)

        await waitForWrites()
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет")
        XCTAssertEqual(sut.edit(for: 7), edit)
        XCTAssertEqual(sut.editingMessageId(for: 7), 15)
        XCTAssertEqual(sut.draft(for: 7), "Черновик")
        XCTAssertEqual(storage.applied.map(\.changes), [[7: .edit(edit)]])
        XCTAssertEqual(storage.drafts[1], [7: "Черновик"])
    }

    /// Кейс: режим редактирования уже включён; включается редактирование другого сообщения.
    /// Ожидание: правка прежняя — повторное включение ничего не меняет.
    func test_beginEditing_whileEditing_keepsCurrentEdit() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)

        sut.beginEditing(messageId: 16, originalText: "Пока", conversationId: 7, userId: 1)

        XCTAssertEqual(sut.edit(for: 7), MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет"))
    }

    /// Кейс: в режиме редактирования меняется текст правки, в том числе на пустой, без точки сохранения.
    /// Ожидание: текст правки меняется только в памяти, режим не выключается, черновик не трогается.
    func test_updateEdit_changesMemoryOnly() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        await waitForWrites()

        sut.updateEdit(text: "Привет всем", conversationId: 7, userId: 1)
        sut.updateEdit(text: "", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(sut.edit(for: 7)?.text, "")
        XCTAssertEqual(sut.editingMessageId(for: 7), 15)
        XCTAssertEqual(sut.draft(for: 7), "Черновик")
        XCTAssertEqual(storage.applied.count, 1)
    }

    /// Кейс: текст правки изменён и сохранён в точке сохранения.
    /// Ожидание: в БД записана правка с новым текстом, черновик в БД на месте.
    func test_saveEdit_writesEditText() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")

        sut.saveEdit(edit, conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(sut.edit(for: 7), edit)
        XCTAssertEqual(storage.edits[1], [7: edit])
        XCTAssertEqual(storage.drafts[1], [7: "Черновик"])
    }

    /// Кейс: правка сохраняется, но режим редактирования уже выключен (например, запрос успел завершиться).
    /// Ожидание: правка не воскрешается ни в памяти, ни в БД.
    func test_saveEdit_withoutEdit_doesNothing() async {
        await sut.load(userId: 1)

        sut.saveEdit(MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем"), conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertNil(sut.edit(for: 7))
        XCTAssertTrue(storage.applied.isEmpty)
    }

    /// Кейс: редактируется сообщение 15; приходит выключение режима для сообщения 16 (поздний ответ прежней правки).
    /// Ожидание: режим не выключен.
    func test_endEditing_otherMessage_keepsEdit() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)

        sut.endEditing(messageId: 16, conversationId: 7, userId: 1)

        XCTAssertEqual(sut.editingMessageId(for: 7), 15)
    }

    /// Кейс: у переписки черновик и правка; режим редактирования выключается.
    /// Ожидание: правки нет ни в памяти, ни в БД; черновик прежний.
    func test_endEditing_clearsEditAndKeepsDraft() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)

        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertNil(sut.edit(for: 7))
        XCTAssertNil(sut.editingMessageId(for: 7))
        XCTAssertEqual(sut.draft(for: 7), "Черновик")
        XCTAssertEqual(storage.edits[1], [:])
        XCTAssertEqual(storage.drafts[1], [7: "Черновик"])
    }

    /// Кейс: в БД правка; сервис загружает данные пользователя.
    /// Ожидание: правка и редактируемое сообщение доступны из памяти.
    func test_load_readsEdits() async {
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")
        storage.edits = [1: [7: edit]]

        await sut.load(userId: 1)

        XCTAssertEqual(sut.edit(for: 7), edit)
        XCTAssertEqual(sut.editingMessageId(for: 7), 15)
        XCTAssertNil(sut.draft(for: 7))
    }

    /// Кейс: за `editingMessageId(for:)` наблюдают; меняются текст правки и черновик, затем режим выключается.
    /// Ожидание: набор текста наблюдателя не будит, выключение режима — будит.
    func test_editingMessageId_notifiesOnlyOnModeChange() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        let changeCount = trackEditingMessageIdChanges(conversationId: 7)

        sut.updateEdit(text: "Привет всем", conversationId: 7, userId: 1)
        sut.update(text: "Черновик другой переписки", conversationId: 8, userId: 1)
        let countAfterTyping = changeCount.value
        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)

        XCTAssertEqual(countAfterTyping, 0)
        XCTAssertEqual(changeCount.value, 1)
    }

    /// Кейс: правка изменена в памяти; запись черновика этой переписки идёт, пока правка снова меняется.
    /// Ожидание: после записи пометка правки не снята — следующее сохранение пишет последний текст правки.
    func test_dirtyFields_trackedPerField() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        await waitForWrites()
        let gate = Gate()
        storage.nextApplyGate = gate
        sut.save(text: "Черновик", conversationId: 7, userId: 1)
        await yieldUntil { gate.isWaiting }
        sut.updateEdit(text: "Привет всем", conversationId: 7, userId: 1)
        gate.open()
        await waitForWrites()

        sut.save(text: "Черновик", conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.edits[1]?[7]?.text, "Привет всем")
        XCTAssertEqual(storage.drafts[1], [7: "Черновик"])
    }

    /// Кейс: чтение упало; у переписки в БД черновик, которого нет в памяти; включается и выключается
    /// редактирование, текст правки сохраняется.
    /// Ожидание: черновик в БД не стёрт ни одной записью — пишется только поле правки.
    func test_editing_afterFailedLoad_keepsUnseenDraft() async {
        storage.drafts = [1: [7: "Невиденный"]]
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)

        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        sut.saveEdit(MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем"), conversationId: 7, userId: 1)
        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.drafts[1], [7: "Невиденный"])
        XCTAssertTrue(storage.applied.allSatisfy { $0.changes[7]?.text == nil })
    }

    /// Кейс: чтение упало; выключается редактирование переписки, правки которой нет в памяти.
    /// Ожидание: ничего не записывается — правку в БД сервис не видел.
    func test_endEditing_afterFailedLoad_withoutEdit_writesNothing() async {
        storage.edits = [1: [7: MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")]]
        storage.stubbedFetchError = URLError(.unknown)
        await sut.load(userId: 1)

        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertTrue(storage.applied.isEmpty)
    }

    /// Кейс: текст правки изменён в памяти без сохранения; начинается выход.
    /// Ожидание: правка записана в БД, память очищена; после повторного входа правка на месте.
    func test_logout_writesDirtyEdit() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        sut.updateEdit(text: "Привет всем", conversationId: 7, userId: 1)

        sut.prepareForLogout()
        await waitForWrites()
        XCTAssertNil(sut.edit(for: 7))
        await sut.load(userId: 1)

        XCTAssertEqual(sut.edit(for: 7), MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем"))
    }

    /// Кейс: у переписки в БД черновик, в памяти — правка; пользователь вышел, экран уходит после выхода
    /// и сохраняет правку, затем выключает режим.
    /// Ожидание: правка записана, затем выключена; черновик, которого нет в памяти, не стёрт.
    func test_editChanges_afterLogout_keepDraft() async {
        storage.drafts = [1: [7: "Черновик"]]
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        sut.prepareForLogout()
        let edit = MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")

        sut.saveEdit(edit, conversationId: 7, userId: 1)
        await waitForWrites()
        let savedEdit = storage.edits[1]?[7]
        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(savedEdit, edit)
        XCTAssertNil(storage.edits[1]?[7])
        XCTAssertEqual(storage.drafts[1], [7: "Черновик"])
    }

    /// Кейс: пользователь вышел без правки в памяти; экран после выхода сохраняет правку.
    /// Ожидание: ничего не записывается — правка не воскрешается.
    func test_saveEdit_afterLogout_withoutEdit_writesNothing() async {
        await sut.load(userId: 1)
        sut.prepareForLogout()

        sut.saveEdit(MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем"), conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertTrue(storage.applied.isEmpty)
    }

    /// Кейс: пользователь вышел с включённой правкой; после выхода режим выключен, затем экран сохраняет ту же правку.
    /// Ожидание: выключение записано, а сохранение после него не воскрешает режим — записей правки больше нет.
    func test_saveEdit_afterLogoutAndEndEditing_doesNotResurrectEdit() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        sut.prepareForLogout()
        sut.endEditing(messageId: 15, conversationId: 7, userId: 1)
        await waitForWrites()
        let appliedBefore = storage.applied.count

        sut.saveEdit(MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем"), conversationId: 7, userId: 1)

        await waitForWrites()
        XCTAssertEqual(storage.applied.count, appliedBefore)
        XCTAssertNil(storage.edits[1]?[7])
    }

    /// Кейс: пользователь вышел с правкой сообщения 15; после выхода приходят сохранение и выключение правки
    /// другого сообщения той же переписки и сохранение от другого пользователя.
    /// Ожидание: ничего из этого не записывается — правка сообщения 15 в БД не тронута.
    func test_editChanges_afterLogout_otherMessageOrUser_writeNothing() async {
        await sut.load(userId: 1)
        sut.beginEditing(messageId: 15, originalText: "Привет", conversationId: 7, userId: 1)
        sut.prepareForLogout()
        await waitForWrites()
        let saved = storage.edits[1]?[7]
        let appliedBefore = storage.applied.count

        sut.saveEdit(MessageEditDraft(messageId: 16, originalText: "Пока", text: "Пока всем"), conversationId: 7, userId: 1)
        sut.endEditing(messageId: 16, conversationId: 7, userId: 1)
        sut.saveEdit(MessageEditDraft(messageId: 15, originalText: "Привет", text: "Чужой текст"), conversationId: 7, userId: 2)

        await waitForWrites()
        XCTAssertEqual(storage.applied.count, appliedBefore)
        XCTAssertEqual(storage.edits[1]?[7], saved)
    }

    /// Кейс: в БД черновик и правка, сохранённые давно; сервис загружает данные.
    /// Ожидание: просроченные записи удаляются одним вызовом с общей границей — срок у черновика и правки общий.
    func test_load_expiryIsSharedForDraftAndEdit() async {
        storage.drafts = [1: [7: "Черновик"]]
        storage.edits = [1: [7: MessageEditDraft(messageId: 15, originalText: "Привет", text: "Привет всем")]]

        await sut.load(userId: 1)

        XCTAssertEqual(storage.deleteCutoffs, [now.addingTimeInterval(-MessageDraftService.draftLifetime)])
    }

    // MARK: - Helpers

    /// Считает изменения `editingMessageId(for:)`, о которых сообщает Observation. Регистрация ставится заново
    /// после каждого срабатывания.
    /// - Parameter conversationId: переписка.
    private func trackEditingMessageIdChanges(conversationId: Int) -> ChangeCounter {
        let counter = ChangeCounter()
        func track() {
            withObservationTracking {
                _ = sut.editingMessageId(for: conversationId)
            } onChange: {
                counter.value += 1
                MainActor.assumeIsolated { track() }
            }
        }
        track()
        return counter
    }

    /// Ждёт, пока закончатся все записи в БД, запущенные сервисом.
    private func waitForWrites() async {
        await waitUntil { [unowned self] in backgroundTasks.runningCount == 0 }
    }
}

/// Счётчик срабатываний Observation.
private final class ChangeCounter: @unchecked Sendable {
    /// Изменяется только на main: в тесте свойства сервиса меняются на main, и `onChange` вызывается там же.
    var value = 0
}
