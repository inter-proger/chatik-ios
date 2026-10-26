//
//  GroupInfoService.swift
//  Chatik
//

import Foundation
import Observation
import os

/// Состав групп для экранов (`docs/group-chats.md`, решение 3). Наблюдаемые значения можно читать и до
/// `beginObserving` (в первом `body` экрана): появление группы в наблюдении тоже наблюдается.
@MainActor
protocol GroupInfoProviding: AnyObject {
    /// Экран группы открыт: состав читается из БД и обновляется запросом, а затем на каждый `connected`. Вызовы
    /// считаются — группа может быть открыта на нескольких экранах и в нескольких сценах.
    /// - Parameter conversationId: группа.
    func beginObserving(conversationId: Int)
    /// Экран группы закрыт; состояние выгружается, когда закрыт последний.
    /// - Parameter conversationId: группа.
    func endObserving(conversationId: Int)
    /// Состав наблюдаемой группы. Наблюдается.
    /// - Parameter conversationId: наблюдаемая группа.
    /// - Returns: `nil` — состава нет ни в памяти, ни в БД, а запрос ещё не ответил.
    func groupInfo(conversationId: Int) -> GroupInfo?
    /// Последний запрос состава не удался; сбрасывается, когда начинается следующий. Наблюдается.
    /// - Parameter conversationId: наблюдаемая группа.
    func isRefreshFailed(conversationId: Int) -> Bool
    /// Запрашивает состав; запрос, который уже идёт, не повторяется.
    /// - Parameter conversationId: группа.
    func refresh(conversationId: Int)
    /// Запрашивает состав и дожидается ответа (pull-to-refresh). Ошибка отмечается в `isRefreshFailed`.
    /// - Parameter conversationId: группа.
    func reload(conversationId: Int) async
    /// Разовый снимок для экрана, который за составом не следит: из памяти, иначе из БД, иначе — ответ того же
    /// запроса, что `refresh`.
    /// - Parameter conversationId: группа.
    func snapshot(conversationId: Int) async throws -> GroupInfo
    /// Состав из памяти без наблюдения — для сервисов.
    /// - Parameter conversationId: группа.
    func currentInfo(conversationId: Int) -> GroupInfo?
    /// Применяет состав из ответа REST (`create`, `addMembers`, `changeOwner`). Сохраняется по версии, даже если
    /// группа не наблюдается.
    /// - Parameter info: состав.
    func apply(_ info: GroupInfo)
}

/// Наблюдатель изменений состава — сервис, которому нужен каждый новый состав (не экран).
@MainActor
protocol GroupInfoObserver: AnyObject {
    /// Применён новый состав группы.
    /// - Parameters:
    ///   - info: состав.
    ///   - isAuthoritative: состав из сети или события; `false` — из БД, он может быть устаревшим: по нему нельзя,
    ///     например, удалять ушедших участников.
    func groupInfoDidChange(_ info: GroupInfo, isAuthoritative: Bool)
}

@MainActor
protocol GroupInfoServiceProtocol: GroupInfoProviding, AuthServiceObserver, ConversationRemovalObserver {
    /// Подписывается на очередь событий и читает из БД группы с сохранённым составом.
    func start()
    /// Добавляет наблюдателя изменений; хранится слабо.
    /// - Parameter observer: наблюдатель.
    func addObserver(_ observer: GroupInfoObserver)
}

/// Состав и роли групп (`GroupInfo`) — единственный писатель `GroupInfoEntity`.
///
/// **Слияние.** Пришедший состав заменяет известный, только если его `version` больше; порядок прихода не важен.
///
/// **Что применяется.** Ответы REST — всегда. События — если группа наблюдается или её состав уже сохранён;
/// исключение — `membersAdded` для добавленного: его состав сохраняется всегда, кроме устаревшего события (версия
/// не новее метки удаления).
@MainActor
final class GroupInfoService: GroupInfoServiceProtocol {
    private let groupService: GroupServiceProtocol
    private let storage: GroupInfoStorageServiceProtocol
    private let eventQueue: RealtimeEventQueueProtocol
    private weak var membership: ConversationMembershipVerifying?
    private weak var removalMarks: ConversationRemovalMarks?
    private var subscription: RealtimeSubscription?
    /// Известные составы — последние применённые в этой сессии.
    private var known: [Int: GroupInfo] = [:]
    /// Наблюдаемые группы.
    private var observed: [Int: GroupInfoState] = [:]
    /// Меняется, когда группа начинает наблюдаться: экран, прочитавший состав до своего `beginObserving`
    /// (в первом `body`), перерисуется, когда состояние появится.
    private let observedRevision = ObservedRevision()
    /// Группы с сохранённым составом; прочитаны при старте и дополняются записями.
    private var storedConversationIds: Set<Int> = []
    private var isStoredLoaded = false
    private var storedIdsTask: Task<Void, Never>?
    /// Идущие запросы состава — один на группу. Токен отличает запрос от более позднего по той же группе.
    private var fetchTasks: [Int: (token: UUID, task: Task<GroupInfo, Error>)] = [:]
    /// Последняя запись в БД: записи идут по порядку.
    private var lastWrite: Task<Void, Never>?
    private var observers: [WeakGroupInfoObserver] = []
    private var generation = 0
    private var isLoggingOut = false

    /// - Parameters:
    ///   - groupService: запрос `getInfo`.
    ///   - storage: хранилище составов.
    ///   - eventQueue: очередь событий WebSocket.
    ///   - membership: проверка членства при `5002`.
    ///   - removalMarks: метки удаления — устаревшее `membersAdded` не сохраняется.
    init(
        groupService: GroupServiceProtocol,
        storage: GroupInfoStorageServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        membership: ConversationMembershipVerifying?,
        removalMarks: ConversationRemovalMarks?
    ) {
        self.groupService = groupService
        self.storage = storage
        self.eventQueue = eventQueue
        self.membership = membership
        self.removalMarks = removalMarks
    }

    func start() {
        if subscription == nil {
            subscription = eventQueue.subscribe { [weak self] event in
                self?.handle(event)
            }
        }
        loadStoredConversationIdsIfNeeded()
    }

    func addObserver(_ observer: GroupInfoObserver) {
        observers.removeAll { $0.value == nil }
        observers.append(WeakGroupInfoObserver(value: observer))
    }

    func beginObserving(conversationId: Int) {
        guard !isLoggingOut else { return }
        if let state = observed[conversationId] {
            state.observerCount += 1
            return
        }
        let state = GroupInfoState(info: known[conversationId])
        observed[conversationId] = state
        observedRevision.value += 1
        let generation = generation
        state.loadTask = Task { [weak self] in
            await self?.loadStored(conversationId: conversationId, generation: generation)
            self?.refresh(conversationId: conversationId)
        }
    }

    func endObserving(conversationId: Int) {
        guard let state = observed[conversationId] else { return }
        state.observerCount -= 1
        guard state.observerCount == 0 else { return }
        state.loadTask?.cancel()
        observed[conversationId] = nil
    }

    func groupInfo(conversationId: Int) -> GroupInfo? {
        _ = observedRevision.value
        return observed[conversationId]?.info
    }

    func isRefreshFailed(conversationId: Int) -> Bool {
        _ = observedRevision.value
        return observed[conversationId]?.isRefreshFailed ?? false
    }

    func currentInfo(conversationId: Int) -> GroupInfo? {
        known[conversationId]
    }

    func refresh(conversationId: Int) {
        guard !isLoggingOut, fetchTasks[conversationId] == nil else { return }
        if let state = observed[conversationId], state.isRefreshFailed {
            state.isRefreshFailed = false
        }
        let task = startFetch(conversationId: conversationId)
        Task { [weak self] in
            do {
                _ = try await task.value
            } catch {
                self?.markRefreshFailed(conversationId: conversationId)
            }
        }
    }

    func reload(conversationId: Int) async {
        guard !isLoggingOut else { return }
        if let state = observed[conversationId], state.isRefreshFailed {
            state.isRefreshFailed = false
        }
        let task = fetchTasks[conversationId]?.task ?? startFetch(conversationId: conversationId)
        do {
            _ = try await task.value
        } catch {
            markRefreshFailed(conversationId: conversationId)
        }
    }

    func snapshot(conversationId: Int) async throws -> GroupInfo {
        if let info = known[conversationId] {
            return info
        }
        let generation = generation
        if let stored = try? await storage.fetch(conversationId: conversationId), generation == self.generation {
            apply(stored, persists: false)
            return known[conversationId] ?? stored
        }
        return try await (fetchTasks[conversationId]?.task ?? startFetch(conversationId: conversationId)).value
    }

    func apply(_ info: GroupInfo) {
        guard !isLoggingOut else { return }
        apply(info, persists: true)
    }

    func authServiceWillLogout() async {
        isLoggingOut = true
        generation += 1
        observed.values.forEach { $0.loadTask?.cancel() }
        fetchTasks.values.forEach { $0.task.cancel() }
        storedIdsTask?.cancel()
        await lastWrite?.value
        known = [:]
        observed = [:]
        fetchTasks = [:]
        storedConversationIds = []
        isStoredLoaded = false
        storedIdsTask = nil
        lastWrite = nil
    }

    func authServiceDidLogout(reason: LogoutReason) async {
        isLoggingOut = false
    }

    func conversationWasRemoved(_ info: RemovedConversationInfo) async {
        let conversationId = info.conversationId
        known[conversationId] = nil
        storedConversationIds.remove(conversationId)
        fetchTasks[conversationId]?.task.cancel()
        fetchTasks[conversationId] = nil
        enqueueWrite { storage in try await storage.delete(conversationId: conversationId) }
        await lastWrite?.value
    }

    // MARK: - События

    /// Применяет событие группы.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) {
        guard !isLoggingOut else { return }
        switch event {
        case .connected:
            observed.keys.forEach { refresh(conversationId: $0) }
            loadStoredConversationIdsIfNeeded()
        case let .group(groupEvent):
            applyEvent(groupEvent)
        case .conversationCreated, .conversationRead, .memberRead, .messageReceived, .messageEdited:
            break
        }
    }

    /// Применяет состав из события по правилам сервиса.
    /// - Parameter event: событие группы.
    private func applyEvent(_ event: GroupEvent) {
        guard let info = event.groupInfo else { return }
        switch event {
        case .created:
            apply(info, persists: true)
        case let .membersAdded(conversationId, _, _, changeVersion?):
            // Добавили текущего пользователя: состав сохраняется всегда, если событие не устарело.
            guard removalMarks?.isRemoved(conversationId: conversationId, changeVersion: changeVersion) != true else { return }
            apply(info, persists: true)
        default:
            let id = info.conversationId
            guard observed[id] != nil || storedConversationIds.contains(id) || !isStoredLoaded else { return }
            // Пока сохранённые группы не прочитаны, хранилище само пропустит группу без записи.
            apply(info, persists: true, createsMissing: observed[id] != nil || storedConversationIds.contains(id))
        }
    }

    // MARK: - Состояние

    /// Применяет состав, если его версия больше известной: память, наблюдаемое состояние, наблюдатели и запись.
    /// - Parameters:
    ///   - info: состав.
    ///   - persists: записать в БД.
    ///   - createsMissing: создавать ли запись группе без сохранённого состава.
    private func apply(_ info: GroupInfo, persists: Bool, createsMissing: Bool = true) {
        let id = info.conversationId
        guard info.version > (known[id]?.version ?? .min) else { return }
        known[id] = info
        if let state = observed[id], state.info != info {
            state.info = info
        }
        if persists {
            if createsMissing {
                storedConversationIds.insert(id)
            }
            enqueueWrite { storage in try await storage.save(info, createsMissing: createsMissing) }
        }
        observers.forEach { $0.value?.groupInfoDidChange(info, isAuthoritative: persists) }
    }

    /// Запускает запрос состава; ответ применяется. На `5002` — проверка членства.
    /// - Parameter conversationId: группа.
    /// - Returns: задача запроса — её ждут `refresh` и `snapshot`.
    private func startFetch(conversationId: Int) -> Task<GroupInfo, Error> {
        let generation = generation
        let token = UUID()
        let applying = Task { [weak self, groupService] () throws -> GroupInfo in
            defer { self?.finishFetch(conversationId: conversationId, token: token) }
            do {
                let info = try await groupService.fetchInfo(conversationId: conversationId)
                guard let self, generation == self.generation else { return info }
                self.apply(info, persists: true)
                return self.known[conversationId] ?? info
            } catch {
                self?.handleFetchError(error, conversationId: conversationId)
                throw error
            }
        }
        fetchTasks[conversationId] = (token, applying)
        return applying
    }

    /// Снимает запрос, если он всё ещё текущий: отменённый старый запрос не затирает запись нового.
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - token: токен завершившегося запроса.
    private func finishFetch(conversationId: Int, token: UUID) {
        guard fetchTasks[conversationId]?.token == token else { return }
        fetchTasks[conversationId] = nil
    }

    /// Логирует ошибку запроса; на `5002` просит проверить членство.
    /// - Parameters:
    ///   - error: ошибка.
    ///   - conversationId: группа.
    private func handleFetchError(_ error: Error, conversationId: Int) {
        guard !(error is CancellationError) else { return }
        Logger.groups.error("Не удалось загрузить состав группы \(conversationId, privacy: .public): \(String(describing: error), privacy: .public)")
        guard error.indicatesLostMembership else { return }
        membership?.verifyMembership(conversationId: conversationId)
    }

    /// Отмечает у наблюдаемой группы, что запрос не удался.
    /// - Parameter conversationId: группа.
    private func markRefreshFailed(conversationId: Int) {
        guard let state = observed[conversationId], !state.isRefreshFailed else { return }
        state.isRefreshFailed = true
    }

    // MARK: - БД

    /// Читает сохранённый состав наблюдаемой группы и применяет его без записи.
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - generation: сессия, в которой начато чтение.
    private func loadStored(conversationId: Int, generation: Int) async {
        do {
            guard let stored = try await storage.fetch(conversationId: conversationId), generation == self.generation else { return }
            apply(stored, persists: false)
        } catch {
            Logger.groups.error("Не удалось прочитать состав группы \(conversationId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Начинает чтение групп с сохранённым составом, если оно ещё не сделано. До `start()` ничего не делает.
    private func loadStoredConversationIdsIfNeeded() {
        guard subscription != nil, !isLoggingOut, !isStoredLoaded, storedIdsTask == nil else { return }
        let generation = generation
        storedIdsTask = Task { [weak self] in
            await self?.loadStoredConversationIds(generation: generation)
        }
    }

    /// Читает группы с сохранённым составом; при сбое следующий повод начнёт чтение заново.
    /// - Parameter generation: сессия, в которой начато чтение.
    private func loadStoredConversationIds(generation: Int) async {
        do {
            let ids = try await storage.fetchConversationIds()
            guard generation == self.generation else { return }
            storedConversationIds.formUnion(ids)
            isStoredLoaded = true
        } catch {
            Logger.groups.error("Не удалось прочитать группы с составом: \(String(describing: error), privacy: .public)")
            guard generation == self.generation else { return }
            storedIdsTask = nil
        }
    }

    /// Ставит запись в БД после предыдущей: записи идут в порядке изменений.
    /// - Parameter operation: запись.
    private func enqueueWrite(_ operation: @escaping @MainActor (GroupInfoStorageServiceProtocol) async throws -> Void) {
        let previous = lastWrite
        let storage = storage
        lastWrite = Task {
            await previous?.value
            do {
                try await operation(storage)
            } catch {
                Logger.groups.error("Не удалось сохранить состав группы: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

/// Состав одной наблюдаемой группы. Наблюдается по отдельности: событие одной группы не перерисовывает экраны других.
@MainActor
@Observable
private final class GroupInfoState {
    var info: GroupInfo?
    var isRefreshFailed = false
    @ObservationIgnored var observerCount = 1
    /// Чтение из БД и первый запрос.
    @ObservationIgnored var loadTask: Task<Void, Never>?

    init(info: GroupInfo?) {
        self.info = info
    }
}

/// Наблюдаемый счётчик появления групп в наблюдении.
@MainActor
@Observable
private final class ObservedRevision {
    var value = 0
}

/// Слабая ссылка на наблюдателя изменений состава.
private struct WeakGroupInfoObserver {
    weak var value: GroupInfoObserver?
}

extension Logger {
    /// Лог групп: сбои, которые не показываются пользователю.
    static let groups = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Groups")
}
