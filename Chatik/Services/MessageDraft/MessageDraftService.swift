//
//  MessageDraftService.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol MessageDraftServiceProtocol: AnyObject, SessionDataLoading {
    /// Текст черновика переписки; `nil` — черновика нет. Читается из памяти, отслеживается Observation.
    func draft(for conversationId: Int) -> String?
    /// `true`, если у переписки есть черновик.
    func hasDraft(for conversationId: Int) -> Bool
    /// Меняет черновик пользователя `userId` в памяти — при каждом изменении поля ввода. БД не трогает.
    func update(text: String, conversationId: Int, userId: Int)
    /// Меняет черновик в памяти, как `update`, и ставит в очередь записи все незаписанные изменения
    /// пользователя `userId` — в точках сохранения.
    func save(text: String, conversationId: Int, userId: Int)
    /// Удаляет черновик пользователя `userId` из памяти и из БД — после отправки сообщения.
    func remove(conversationId: Int, userId: Int)

    /// Незавершённое редактирование переписки вместе с набранным текстом; `nil` — режим выключен. Читается
    /// из памяти, отслеживается Observation и меняется при каждом изменении текста правки.
    func edit(for conversationId: Int) -> MessageEditDraft?
    /// Редактируемое сообщение переписки; `nil` — режим выключен. Отслеживается Observation и меняется только
    /// при включении и выключении режима — для тех, кому текст правки не нужен (список чатов).
    func editingMessageId(for conversationId: Int) -> Int?
    /// Включает режим редактирования с исходным текстом сообщения и сразу ставит запись в очередь — точка
    /// сохранения. Черновик не меняется. Если режим уже включён, ничего не делает.
    func beginEditing(messageId: Int, originalText: String, conversationId: Int, userId: Int)
    /// Меняет текст правки в памяти — при каждом изменении поля ввода в режиме редактирования. БД не трогает.
    func updateEdit(text: String, conversationId: Int, userId: Int)
    /// Меняет текст правки, как `updateEdit`, и ставит в очередь записи все незаписанные изменения — в точках
    /// сохранения. Для вышедшего пользователя записывает правку целиком, поэтому принимает её, а не только текст.
    func saveEdit(_ edit: MessageEditDraft, conversationId: Int, userId: Int)
    /// Выключает режим редактирования сообщения `messageId` и ставит запись в очередь. Если редактируется другое
    /// сообщение, ничего не делает: поздний ответ на прежнюю правку не должен закрыть новую.
    func endEditing(messageId: Int, conversationId: Int, userId: Int)
}

/// Реакция сервиса черновиков на выход — всё, что о нём знает `MessageDraftLogoutObserver`.
@MainActor
protocol MessageDraftLogoutHandling: AnyObject {
    /// Сессия заканчивается: незаписанные изменения уходят в очередь записи, память очищается.
    func prepareForLogout()
}

/// Состояние полей ввода переписок: черновики сообщений и незавершённые правки своих сообщений. Единственный,
/// кто читает и пишет их в БД.
///
/// В памяти — состояние текущего пользователя: черновики (`conversationId` → текст) и правки. Чтение синхронное
/// и отслеживается Observation: список чатов перерисовывается, когда черновик или режим редактирования меняется.
/// Экран переписки меняет память при каждом изменении поля ввода (`update`, `updateEdit`), а в БД изменения уходят
/// в точках сохранения (`save`, `remove`, `saveEdit`, `beginEditing`, `endEditing`) — одной пачкой и строго
/// по очереди. Неудавшаяся запись не теряется: поле переписки остаётся помеченным и уходит со следующей пачкой.
///
/// Черновик и правка переписки лежат в одной записи БД, но пишутся по отдельности — только изменённые поля.
/// Сервис не всегда знает оба поля (черновики не загрузились, пользователь вышел), и запись целиком стёрла бы
/// невидимое поле. Текст правки не обрезается: пустое поле в режиме редактирования — всё ещё режим редактирования.
///
/// Черновик пустой, если после обрезки `MessageTextValidator.trimmedCharacters` в нём ничего не осталось, —
/// так же сервер решает, пусто ли сообщение. Непустой хранится как есть, без обрезки.
///
/// Черновики переживают выход из аккаунта: пользователей разделяет ключ записи в БД, а не очистка. Черновики,
/// которые не сохранялись дольше `draftLifetime`, удаляются при загрузке — у всех пользователей устройства.
/// Изменения принимаются только от пользователя, чьи черновики загружены, или от вышедшего пользователя —
/// экран переписки может уйти уже после выхода, и набранный текст всё равно записывается ему в БД.
@MainActor
@Observable
final class MessageDraftService: MessageDraftServiceProtocol, MessageDraftLogoutHandling {
    /// Чьи черновики в памяти и что с ними можно делать.
    private enum State: Equatable {
        /// Загрузки ещё не было: изменения не принимаются.
        case idle
        /// Черновики пользователя загружены в память.
        case loaded(userId: Int)
        /// Загрузка не удалась: в памяти только набранное в этой сессии. Пустой текст для переписки, которой
        /// нет в памяти, ничего не удаляет — поле было пустым, потому что черновик не загрузился.
        case loadFailed(userId: Int)
        /// Сессия пользователя закончилась: память пуста, его изменения пишутся только в БД.
        /// `deletableConversationIds` — переписки, черновики которых на момент выхода были в памяти или ждали
        /// записи: только у них пустой текст удаляет черновик. У остальных черновика в БД либо нет, либо он не
        /// загрузился (`loadFailed`), и пустое поле означает не «стёр», а «не видел». `editConversationIds` —
        /// то же для правок: только их можно записать или выключить.
        case loggedOut(userId: Int, deletableConversationIds: Set<Int>, editConversationIds: Set<Int>)
    }

    /// Черновики, которые видит интерфейс.
    private var drafts: [Int: String] = [:]
    /// Незавершённые правки с набранным текстом.
    private var edits: [Int: MessageEditDraft] = [:]
    /// Редактируемые сообщения: меняются только при включении и выключении режима, а не при наборе текста —
    /// наблюдатели режима не перерисовываются на каждое нажатие клавиши.
    private var editingMessageIds: [Int: Int] = [:]
    @ObservationIgnored private var state = State.idle
    /// Поля переписок, изменённые в памяти и ещё не записанные в БД (в том числе после неудачной записи).
    @ObservationIgnored private var dirtyFields: [Int: MessageDraftFields] = [:]
    /// Растёт при каждой смене владельца памяти (загрузка, выход): поздние результаты к новому владельцу
    /// не применяются.
    @ObservationIgnored private var generation = 0
    /// Последняя запись в БД: следующая начинается только после неё.
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    /// Последняя загрузка: следующая начинается только после неё.
    @ObservationIgnored private var pendingLoad: Task<Void, Never>?

    /// Сколько черновик живёт без сохранений: более старые удаляются при загрузке — так не копятся черновики
    /// пропавших переписок и пользователей, которые больше не входят на этом устройстве.
    static let draftLifetime: TimeInterval = 30 * 24 * 60 * 60

    private let storage: MessageDraftStorageServiceProtocol
    private let backgroundTasks: BackgroundTaskRunning
    private let now: () -> Date

    /// - Parameters:
    ///   - storage: хранилище черновиков.
    ///   - backgroundTasks: фоновые задачи системы — запись не прерывается при уходе приложения в фон.
    ///   - now: текущее время — от него отсчитывается срок жизни черновиков; подменяется в тестах.
    init(
        storage: MessageDraftStorageServiceProtocol,
        backgroundTasks: BackgroundTaskRunning,
        now: @escaping () -> Date = { Date() }
    ) {
        self.storage = storage
        self.backgroundTasks = backgroundTasks
        self.now = now
    }

    /// Текст черновика переписки из памяти.
    /// - Parameter conversationId: переписка.
    func draft(for conversationId: Int) -> String? {
        drafts[conversationId]
    }

    /// `true`, если у переписки есть черновик.
    /// - Parameter conversationId: переписка.
    func hasDraft(for conversationId: Int) -> Bool {
        draft(for: conversationId) != nil
    }

    /// Незавершённое редактирование переписки из памяти.
    /// - Parameter conversationId: переписка.
    func edit(for conversationId: Int) -> MessageEditDraft? {
        edits[conversationId]
    }

    /// Редактируемое сообщение переписки из памяти.
    /// - Parameter conversationId: переписка.
    func editingMessageId(for conversationId: Int) -> Int? {
        editingMessageIds[conversationId]
    }

    // MARK: - Загрузка

    /// Загружает черновики пользователя: дожидается предыдущей загрузки и очереди записи (поздняя запись прошлой
    /// сессии должна попасть в БД раньше чтения), удаляет просроченные черновики и читает. Ошибка удаления
    /// логируется и загрузку не останавливает. Ошибка чтения логируется, и до следующей загрузки сервис
    /// принимает изменения только «на запись» (`State.loadFailed`).
    /// - Parameter userId: пользователь открытой сессии.
    func load(userId: Int) async {
        let previous = pendingLoad
        let loading = Task { [weak self] in
            await previous?.value
            await self?.performLoad(userId: userId)
        }
        pendingLoad = loading
        await loading.value
    }

    /// Удаляет просроченные черновики, читает черновики пользователя из БД и делает его владельцем памяти. Если он
    /// уже владелец с загруженными черновиками — ничего не делает; если за время чтения сессия закончилась —
    /// результат отбрасывается.
    /// - Parameter userId: пользователь открытой сессии.
    private func performLoad(userId: Int) async {
        guard state != .loaded(userId: userId) else { return }
        await pendingWrite?.value
        await deleteExpiredDrafts()
        let loadGeneration = generation
        let fetched: [Int: MessageDraft]?
        do {
            fetched = try await storage.fetchAll(userId: userId)
        } catch {
            Logger.storage.error("Не удалось загрузить черновики: \(String(describing: error), privacy: .public)")
            fetched = nil
        }
        guard loadGeneration == generation else { return }
        setMemory(fetched ?? [:])
        state = fetched == nil ? .loadFailed(userId: userId) : .loaded(userId: userId)
        dirtyFields = [:]
        generation += 1
    }

    /// Удаляет черновики, которые не сохранялись дольше `draftLifetime`. Вызывается после очереди записи:
    /// только что сохранённый черновик удаление не задевает.
    private func deleteExpiredDrafts() async {
        do {
            try await storage.deleteAll(updatedBefore: now().addingTimeInterval(-Self.draftLifetime))
        } catch {
            Logger.storage.error("Не удалось удалить просроченные черновики: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Изменения

    /// Меняет черновик в памяти; изменения от пользователя, чьи черновики не в памяти, игнорируются.
    /// - Parameters:
    ///   - text: текст поля ввода.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func update(text: String, conversationId: Int, userId: Int) {
        guard ownerUserId == userId else { return }
        applyToMemory(text: text, conversationId: conversationId)
    }

    /// Меняет черновик в памяти и ставит в очередь записи все незаписанные изменения. Для вышедшего пользователя
    /// память не трогается — в БД записывается только эта переписка; пустой текст удаляет черновик, только если
    /// переписка была в памяти или ждала записи к моменту выхода (или сохранялась после него).
    /// - Parameters:
    ///   - text: текст поля ввода.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func save(text: String, conversationId: Int, userId: Int) {
        if ownerUserId == userId {
            applyToMemory(text: text, conversationId: conversationId)
            flush(userId: userId)
        } else if case .loggedOut(userId, var deletableConversationIds, let editConversationIds) = state {
            let draftText = Self.draftText(text)
            guard draftText != nil || deletableConversationIds.contains(conversationId) else { return }
            enqueueWrite([conversationId: .draft(draftText)], userId: userId)
            deletableConversationIds.insert(conversationId)
            state = .loggedOut(userId: userId, deletableConversationIds: deletableConversationIds, editConversationIds: editConversationIds)
        }
    }

    /// Удаляет черновик: то же, что сохранение пустого текста.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func remove(conversationId: Int, userId: Int) {
        save(text: "", conversationId: conversationId, userId: userId)
    }

    /// Ставит в очередь записи незаписанные изменения, очищает память и запоминает вышедшего пользователя.
    func prepareForLogout() {
        guard let userId = ownerUserId else { return }
        flush(userId: userId)
        let deletableConversationIds = conversationIds(dirtyIn: .text).union(drafts.keys)
        let editConversationIds = conversationIds(dirtyIn: .edit).union(edits.keys)
        setMemory([:])
        dirtyFields = [:]
        state = .loggedOut(userId: userId, deletableConversationIds: deletableConversationIds, editConversationIds: editConversationIds)
        generation += 1
    }

    /// Заменяет память состояниями полей ввода.
    /// - Parameter fields: состояния по `conversationId`.
    private func setMemory(_ fields: [Int: MessageDraft]) {
        drafts = fields.compactMapValues(\.text)
        edits = fields.compactMapValues(\.edit)
        editingMessageIds = edits.mapValues(\.messageId)
    }

    /// Переписки, у которых помечено незаписанным указанное поле.
    /// - Parameter field: поле.
    private func conversationIds(dirtyIn field: MessageDraftFields) -> Set<Int> {
        Set(dirtyFields.filter { $0.value.contains(field) }.keys)
    }

    /// Пользователь, чьи черновики в памяти и чьи изменения принимаются; `nil` — таких нет.
    private var ownerUserId: Int? {
        switch state {
        case let .loaded(userId), let .loadFailed(userId): userId
        case .idle, .loggedOut: nil
        }
    }

    /// Записывает текст в память и помечает переписку незаписанной, если черновик изменился. Пустой текст
    /// для переписки без черновика ничего не меняет: в `loaded` удалять нечего, в `loadFailed` — нельзя.
    /// - Parameters:
    ///   - text: текст поля ввода.
    ///   - conversationId: переписка.
    private func applyToMemory(text: String, conversationId: Int) {
        let newValue = Self.draftText(text)
        guard newValue != drafts[conversationId] else { return }
        drafts[conversationId] = newValue
        dirtyFields[conversationId, default: []].insert(.text)
    }

    // MARK: - Редактирование

    /// Включает режим редактирования и ставит запись в очередь. Изменения от пользователя, чьи черновики
    /// не в памяти, игнорируются: включить режим можно только на открытом экране текущей сессии.
    /// - Parameters:
    ///   - messageId: редактируемое сообщение.
    ///   - originalText: текст сообщения на момент включения.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func beginEditing(messageId: Int, originalText: String, conversationId: Int, userId: Int) {
        guard ownerUserId == userId else { return }
        guard edits[conversationId] == nil else {
            Logger.storage.error("Режим редактирования уже включён: повторное включение пропущено")
            return
        }
        edits[conversationId] = MessageEditDraft(messageId: messageId, originalText: originalText, text: originalText)
        editingMessageIds[conversationId] = messageId
        dirtyFields[conversationId, default: []].insert(.edit)
        flush(userId: userId)
    }

    /// Меняет текст правки в памяти. Режим выключен или изменение от чужого пользователя — ничего не делает.
    /// - Parameters:
    ///   - text: текст поля ввода, как есть.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func updateEdit(text: String, conversationId: Int, userId: Int) {
        guard ownerUserId == userId, var edit = edits[conversationId], edit.text != text else { return }
        edit.text = text
        edits[conversationId] = edit
        dirtyFields[conversationId, default: []].insert(.edit)
    }

    /// Меняет текст правки в памяти и ставит в очередь записи все незаписанные изменения. Правка другого сообщения
    /// или выключенный режим не воскрешаются. Для вышедшего пользователя записывается только эта переписка и только
    /// если её правка была в памяти к моменту выхода.
    /// - Parameters:
    ///   - edit: правка с текстом поля ввода.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func saveEdit(_ edit: MessageEditDraft, conversationId: Int, userId: Int) {
        if ownerUserId == userId {
            guard edits[conversationId]?.messageId == edit.messageId else { return }
            updateEdit(text: edit.text, conversationId: conversationId, userId: userId)
            flush(userId: userId)
        } else if case let .loggedOut(userId, _, editConversationIds) = state, editConversationIds.contains(conversationId) {
            enqueueWrite([conversationId: .edit(edit)], userId: userId)
        }
    }

    /// Выключает режим редактирования и ставит запись в очередь. Черновик не меняется.
    /// - Parameters:
    ///   - messageId: сообщение, редактирование которого закончилось.
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки.
    func endEditing(messageId: Int, conversationId: Int, userId: Int) {
        if ownerUserId == userId {
            guard edits[conversationId]?.messageId == messageId else { return }
            edits[conversationId] = nil
            editingMessageIds[conversationId] = nil
            dirtyFields[conversationId, default: []].insert(.edit)
            flush(userId: userId)
        } else if case let .loggedOut(userId, _, editConversationIds) = state, editConversationIds.contains(conversationId) {
            enqueueWrite([conversationId: .edit(nil)], userId: userId)
        }
    }

    // MARK: - Запись в БД

    /// Ставит в очередь записи все незаписанные поля: значения из памяти или удаление.
    /// - Parameter userId: владелец памяти.
    private func flush(userId: Int) {
        guard !dirtyFields.isEmpty else { return }
        enqueueWrite(dirtyChanges, userId: userId)
    }

    /// Изменения для записи в БД: помеченные поля каждой переписки со значениями из памяти.
    private var dirtyChanges: [Int: MessageDraftChange] {
        Dictionary(uniqueKeysWithValues: dirtyFields.map { conversationId, fields in
            let change = MessageDraftChange(
                text: fields.contains(.text) ? .some(drafts[conversationId]) : nil,
                edit: fields.contains(.edit) ? .some(edits[conversationId]) : nil
            )
            return (conversationId, change)
        })
    }

    /// Ставит пачку изменений в очередь: запись начинается после предыдущей и выполняется внутри фоновой задачи
    /// системы, запрошенной сразу, — до того, как приложение успеет приостановиться.
    /// - Parameters:
    ///   - changes: изменения по `conversationId`.
    ///   - userId: пользователь, набравший черновики.
    private func enqueueWrite(_ changes: [Int: MessageDraftChange], userId: Int) {
        let previous = pendingWrite
        let writeGeneration = generation
        let storage = storage
        pendingWrite = backgroundTasks.run(named: "MessageDraftWrite") { [weak self] in
            await previous?.value
            do {
                try await storage.apply(changes, userId: userId)
                self?.didWrite(changes, generation: writeGeneration)
            } catch {
                Logger.storage.error("Не удалось записать черновики: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Снимает пометку с записанных полей, значение которых в памяти не изменилось за время записи.
    /// - Parameters:
    ///   - changes: записанные изменения.
    ///   - generation: поколение, в котором собрана пачка; сменилось — память уже другого владельца.
    private func didWrite(_ changes: [Int: MessageDraftChange], generation: Int) {
        guard generation == self.generation else { return }
        for (conversationId, change) in changes {
            var fields = dirtyFields[conversationId] ?? []
            if change.text == .some(drafts[conversationId]) {
                fields.remove(.text)
            }
            if change.edit == .some(edits[conversationId]) {
                fields.remove(.edit)
            }
            dirtyFields[conversationId] = fields.isEmpty ? nil : fields
        }
    }

    /// Текст черновика из текста поля ввода.
    /// - Parameter text: текст поля ввода.
    /// - Returns: `nil`, если после обрезки ничего не осталось; иначе текст без изменений.
    private static func draftText(_ text: String) -> String? {
        text.trimmingCharacters(in: MessageTextValidator.trimmedCharacters).isEmpty ? nil : text
    }
}

/// Поля состояния поля ввода переписки — для пометки незаписанного.
struct MessageDraftFields: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// Черновик нового сообщения.
    static let text = MessageDraftFields(rawValue: 1 << 0)
    /// Незавершённое редактирование.
    static let edit = MessageDraftFields(rawValue: 1 << 1)
}

/// Передаёт сервису черновиков выход из аккаунта; `AuthService` держит наблюдателей слабо.
@MainActor
final class MessageDraftLogoutObserver: AuthServiceObserver {
    private let draftService: MessageDraftLogoutHandling

    /// - Parameter draftService: сервис черновиков.
    init(draftService: MessageDraftLogoutHandling) {
        self.draftService = draftService
    }

    /// Выход начинается: незаписанные черновики уходят в БД, память очищается. Ждать записи не нужно —
    /// черновики при выходе не удаляются, и поздняя запись ничего не портит.
    func authServiceWillLogout() async {
        draftService.prepareForLogout()
    }
}
