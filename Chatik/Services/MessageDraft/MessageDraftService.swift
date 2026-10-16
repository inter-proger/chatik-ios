//
//  MessageDraftService.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol MessageDraftServiceProtocol: AnyObject, MessageDraftLoading {
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
}

/// Загрузка черновиков при открытии сессии — всё, что о сервисе черновиков знает `SessionService`.
@MainActor
protocol MessageDraftLoading: AnyObject {
    /// Загружает черновики пользователя из БД в память; повторный вызов для того же пользователя после успешной
    /// загрузки ничего не делает.
    func load(userId: Int) async
}

/// Реакция сервиса черновиков на выход — всё, что о нём знает `MessageDraftLogoutObserver`.
@MainActor
protocol MessageDraftLogoutHandling: AnyObject {
    /// Сессия заканчивается: незаписанные изменения уходят в очередь записи, память очищается.
    func prepareForLogout()
}

/// Черновики сообщений: единственный, кто читает и пишет их в БД.
///
/// В памяти — черновики текущего пользователя (`conversationId` → текст). Чтение синхронное и отслеживается
/// Observation: список чатов перерисовывается, когда черновик меняется. Экран переписки меняет память при каждом
/// изменении поля ввода (`update`), а в БД изменения уходят в точках сохранения (`save`, `remove`) — одной пачкой
/// и строго по очереди. Неудавшаяся запись не теряется: переписка остаётся помеченной и уходит со следующей пачкой.
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
        /// `deletableConversationIds` — переписки, которые на момент выхода были в памяти или ждали записи:
        /// только у них пустой текст удаляет черновик. У остальных черновика в БД либо нет, либо он не
        /// загрузился (`loadFailed`), и пустое поле означает не «стёр», а «не видел».
        case loggedOut(userId: Int, deletableConversationIds: Set<Int>)
    }

    /// Черновики, которые видит интерфейс.
    private var drafts: [Int: String] = [:]
    @ObservationIgnored private var state = State.idle
    /// Переписки, изменённые в памяти и ещё не записанные в БД (в том числе после неудачной записи).
    @ObservationIgnored private var dirtyConversationIds: Set<Int> = []
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
        let fetched: [Int: String]?
        do {
            fetched = try await storage.fetchAll(userId: userId)
        } catch {
            Logger.storage.error("Не удалось загрузить черновики: \(String(describing: error), privacy: .public)")
            fetched = nil
        }
        guard loadGeneration == generation else { return }
        drafts = fetched ?? [:]
        state = fetched == nil ? .loadFailed(userId: userId) : .loaded(userId: userId)
        dirtyConversationIds = []
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
        } else if case .loggedOut(userId, var deletableConversationIds) = state {
            let draftText = Self.draftText(text)
            guard draftText != nil || deletableConversationIds.contains(conversationId) else { return }
            enqueueWrite([conversationId: Self.change(for: draftText)], userId: userId)
            deletableConversationIds.insert(conversationId)
            state = .loggedOut(userId: userId, deletableConversationIds: deletableConversationIds)
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
        let deletableConversationIds = dirtyConversationIds.union(drafts.keys)
        drafts = [:]
        dirtyConversationIds = []
        state = .loggedOut(userId: userId, deletableConversationIds: deletableConversationIds)
        generation += 1
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
        dirtyConversationIds.insert(conversationId)
    }

    // MARK: - Запись в БД

    /// Ставит в очередь записи все незаписанные переписки: текст из памяти или удаление.
    /// - Parameter userId: владелец памяти.
    private func flush(userId: Int) {
        guard !dirtyConversationIds.isEmpty else { return }
        let changes = dirtyConversationIds.map { ($0, Self.change(for: drafts[$0])) }
        enqueueWrite(Dictionary(uniqueKeysWithValues: changes), userId: userId)
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

    /// Снимает пометку с записанных переписок, текст которых в памяти не изменился за время записи.
    /// - Parameters:
    ///   - changes: записанные изменения.
    ///   - generation: поколение, в котором собрана пачка; сменилось — память уже другого владельца.
    private func didWrite(_ changes: [Int: MessageDraftChange], generation: Int) {
        guard generation == self.generation else { return }
        for (conversationId, change) in changes where change == Self.change(for: drafts[conversationId]) {
            dirtyConversationIds.remove(conversationId)
        }
    }

    /// Текст черновика из текста поля ввода.
    /// - Parameter text: текст поля ввода.
    /// - Returns: `nil`, если после обрезки ничего не осталось; иначе текст без изменений.
    private static func draftText(_ text: String) -> String? {
        text.trimmingCharacters(in: MessageTextValidator.trimmedCharacters).isEmpty ? nil : text
    }

    /// Изменение для записи в БД.
    /// - Parameter text: текст черновика; `nil` — черновика нет.
    private static func change(for text: String?) -> MessageDraftChange {
        text.map(MessageDraftChange.save) ?? .delete
    }
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
