//
//  MemberReadService.swift
//  Chatik
//

import Foundation
import Observation
import os

/// Прочтение переписки другими участниками — всё, что о нём знает экран переписки. Наблюдаемые значения читаются
/// только после `beginObserving`: появление переписки в наблюдении само по себе не наблюдается
/// (`docs/read-receipts.md`, решение 1).
@MainActor
protocol MemberReadProviding: AnyObject {
    /// Экран переписки открыт: мета читается из БД и обновляется запросом. Вызовы считаются — одна переписка может
    /// быть открыта в нескольких сценах.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - isGroup: групповая переписка — прочтение учитывает состав из `GroupInfo` и время вступления.
    func beginObserving(conversationId: Int, isGroup: Bool)
    /// Экран переписки закрыт; мета выгружается из памяти, когда закрыт последний.
    /// - Parameter conversationId: переписка.
    func endObserving(conversationId: Int)
    /// Указатели прочтения участников, кроме текущего пользователя, по `userId`. Наблюдается.
    /// - Parameter conversationId: наблюдаемая переписка.
    /// - Returns: `nil` — меты нет ни в памяти, ни в БД или переписка не наблюдается.
    func pointers(conversationId: Int) -> [Int: Int]?
    /// Сообщения, прочитанные хотя бы одним участником. Наблюдается и меняется только вместе с галочками.
    /// - Parameter conversationId: наблюдаемая переписка.
    /// - Returns: `nil` — меты нет, а у группы — ещё нет и состава.
    func coverage(conversationId: Int) -> MessageReadCoverage?
    /// Последнее сообщение группы на момент вступления каждого участника из текущего состава. Наблюдается.
    /// - Parameter conversationId: наблюдаемая переписка.
    /// - Returns: `nil` — не группа (учитываются все участники) или состав неизвестен.
    func joinedAfterMessageIds(conversationId: Int) -> [Int: Int]?
    /// Наблюдаемая группа, состав которой ещё неизвестен: кто прочитал, сказать нельзя. Наблюдается.
    /// - Parameter conversationId: наблюдаемая переписка.
    func isAwaitingGroupInfo(conversationId: Int) -> Bool
    /// Последний запрос указателей не удался; сбрасывается, когда начинается следующий. Наблюдается.
    /// - Parameter conversationId: наблюдаемая переписка.
    func isRefreshFailed(conversationId: Int) -> Bool
    /// Запрашивает указатели с сервера; запрос, который уже идёт, не повторяется.
    /// - Parameter conversationId: наблюдаемая переписка.
    func refresh(conversationId: Int)
}

extension MemberReadProviding {
    /// Начинает наблюдение личной переписки.
    /// - Parameter conversationId: переписка.
    func beginObserving(conversationId: Int) {
        beginObserving(conversationId: conversationId, isGroup: false)
    }
}

@MainActor
protocol MemberReadServiceProtocol: MemberReadProviding, AuthServiceObserver, ConversationRemovalObserver, GroupInfoObserver {
    /// Подписывается на очередь событий и читает из БД переписки с сохранённой метой. Повторный вызов
    /// в той же сессии ничего не делает.
    func start()
}

/// Указатели прочтения других участников (`docs/read-receipts.md`, решения 1–4).
///
/// **Слияние по максимуму.** Указатель только растёт, поэтому значения из БД, ответа `getMembersReadMeta`
/// и событий сливаются по максимуму в любом порядке — аренда очереди событий не нужна. Одно исключение — состав
/// участников: участники, которых нет в ответе, удаляются.
///
/// **Что в памяти.** Указатели — только у наблюдаемых переписок (открыт экран). Для остальных есть множество
/// переписок с сохранённой метой: по нему событие решает, нужно ли обновить БД, не читая её. Пока множество
/// не прочитано, событие уходит в БД с условием «только если мета есть» — хранилище проверит это само.
///
/// **Покрытие для галочек** (`coverage`) — отдельное наблюдаемое свойство, которое присваивается только при изменении:
/// лента читает его, а не указатели, и не пересобирается на каждое событие. В личной переписке оно только растёт;
/// в группе считается по участникам текущего `GroupInfo` и их времени вступления (`docs/group-chats.md`, решение 7) —
/// ушедший участник перестаёт учитываться.
///
/// **Запись в БД** склеивается: изменения копятся по переписке и уходят одной фоновой задачей, следующие ждут
/// очередную. При выходе из аккаунта несохранённые изменения отбрасываются, идущая запись дожидается.
@MainActor
final class MemberReadService: MemberReadServiceProtocol {
    private let conversationService: ConversationServiceProtocol
    private let storage: MemberReadStorageServiceProtocol
    private let eventQueue: RealtimeEventQueueProtocol
    private let sessionService: SessionServiceProtocol
    /// Проверка членства: ответ `5002` — возможно, пользователя удалили из группы.
    private weak var membership: ConversationMembershipVerifying?
    /// Состав групп — кто учитывается в прочтении группы.
    private weak var groupInfo: GroupInfoProviding?
    private var subscription: RealtimeSubscription?
    /// Наблюдаемые переписки.
    private var observed: [Int: ConversationMemberReads] = [:]
    /// Переписки, у которых в БД есть мета: прочитаны при старте и дополняются записями.
    private var storedConversationIds: Set<Int> = []
    /// `storedConversationIds` прочитано из БД в этой сессии.
    private var isStoredLoaded = false
    /// Чтение `storedConversationIds`; `nil` — сессия ещё не начата.
    private var storedIdsTask: Task<Void, Never>?
    /// Изменения, ждущие записи в БД, по переписке.
    private var pendingWrites: [Int: MemberReadWrite] = [:]
    /// Идущая запись в БД.
    private var writeTask: Task<Void, Never>?
    /// Растёт при выходе из аккаунта: результаты, начатые в прежней сессии, не применяются.
    private var generation = 0
    private var isLoggingOut = false

    /// - Parameters:
    ///   - conversationService: запрос `getMembersReadMeta`.
    ///   - storage: хранилище меты.
    ///   - eventQueue: очередь событий WebSocket.
    ///   - sessionService: текущий пользователь — его сообщения не двигают указатели.
    ///   - membership: проверка членства при ответе `5002`.
    ///   - groupInfo: состав групп.
    init(
        conversationService: ConversationServiceProtocol,
        storage: MemberReadStorageServiceProtocol,
        eventQueue: RealtimeEventQueueProtocol,
        sessionService: SessionServiceProtocol,
        membership: ConversationMembershipVerifying?,
        groupInfo: GroupInfoProviding?
    ) {
        self.conversationService = conversationService
        self.storage = storage
        self.eventQueue = eventQueue
        self.sessionService = sessionService
        self.membership = membership
        self.groupInfo = groupInfo
    }

    /// Подписывается на очередь (подписка переживает выход из аккаунта) и читает переписки с сохранённой метой.
    func start() {
        if subscription == nil {
            subscription = eventQueue.subscribe { [weak self] event in
                self?.handle(event)
            }
        }
        loadStoredConversationIdsIfNeeded()
    }

    func beginObserving(conversationId: Int, isGroup: Bool) {
        guard !isLoggingOut else { return }
        loadStoredConversationIdsIfNeeded()
        if let state = observed[conversationId] {
            state.observerCount += 1
            return
        }
        let state = ConversationMemberReads(isGroup: isGroup)
        observed[conversationId] = state
        let generation = generation
        state.loadTask = Task { [weak self] in
            await self?.loadStored(conversationId: conversationId, state: state, generation: generation)
            self?.refresh(conversationId: conversationId)
        }
    }

    func endObserving(conversationId: Int) {
        guard let state = observed[conversationId] else { return }
        state.observerCount -= 1
        guard state.observerCount == 0 else { return }
        state.cancelTasks()
        observed[conversationId] = nil
    }

    func pointers(conversationId: Int) -> [Int: Int]? {
        observed[conversationId]?.pointers
    }

    func coverage(conversationId: Int) -> MessageReadCoverage? {
        observed[conversationId]?.coverage
    }

    func isAwaitingGroupInfo(conversationId: Int) -> Bool {
        guard observed[conversationId]?.isGroup == true else { return false }
        return groupInfo?.groupInfo(conversationId: conversationId) == nil
    }

    func joinedAfterMessageIds(conversationId: Int) -> [Int: Int]? {
        guard observed[conversationId]?.isGroup == true,
              let info = groupInfo?.groupInfo(conversationId: conversationId) else { return nil }
        return Dictionary(info.members.map { ($0.userId, $0.joinedAfterMessageId) }, uniquingKeysWith: max)
    }

    /// Применён новый состав группы: покрытие наблюдаемой группы пересчитывается — новые участники начинают
    /// учитываться. Участники, которых в составе нет, удаляются из меты (в памяти и в БД) — только по составу из сети
    /// или события: сохранённый в БД мог устареть, и по нему пропали бы указатели недавно вступивших.
    /// - Parameters:
    ///   - info: состав группы.
    ///   - isAuthoritative: состав из сети или события.
    func groupInfoDidChange(_ info: GroupInfo, isAuthoritative: Bool) {
        guard !isLoggingOut else { return }
        let conversationId = info.conversationId
        let members = Set(info.members.map(\.userId))
        if let state = observed[conversationId], let pointers = state.pointers {
            publish(isAuthoritative ? pointers.filter { members.contains($0.key) } : pointers, in: state, conversationId: conversationId)
        }
        guard isAuthoritative, observed[conversationId] != nil || storedConversationIds.contains(conversationId) else { return }
        enqueueWrite(MemberReadWrite(pointers: [:], members: members, createsMissing: false), conversationId: conversationId)
    }

    func isRefreshFailed(conversationId: Int) -> Bool {
        observed[conversationId]?.isRefreshFailed ?? false
    }

    func refresh(conversationId: Int) {
        guard !isLoggingOut, let state = observed[conversationId], state.refreshTask == nil else { return }
        let generation = generation
        if state.isRefreshFailed {
            state.isRefreshFailed = false
        }
        state.refreshTask = Task { [weak self] in
            await self?.performRefresh(conversationId: conversationId, state: state, generation: generation)
            state.refreshTask = nil
        }
    }

    /// Выход начинается: запросы отменяются, несохранённые изменения отбрасываются, идущая запись дожидается —
    /// после выхода БД очищается, и поздняя запись досталась бы следующему пользователю. Память сбрасывается.
    func authServiceWillLogout() async {
        isLoggingOut = true
        generation += 1
        observed.values.forEach { $0.cancelTasks() }
        storedIdsTask?.cancel()
        pendingWrites = [:]
        await writeTask?.value
        observed = [:]
        storedConversationIds = []
        isStoredLoaded = false
        storedIdsTask = nil
    }

    func authServiceDidLogout(reason: LogoutReason) async {
        isLoggingOut = false
    }

    /// Пользователь больше не участник переписки: её мета удаляется из памяти и БД после уже начатой записи.
    /// - Parameter info: удалённая переписка.
    func conversationWasRemoved(_ info: RemovedConversationInfo) async {
        let conversationId = info.conversationId
        observed[conversationId]?.cancelTasks()
        observed[conversationId] = nil
        storedConversationIds.remove(conversationId)
        pendingWrites[conversationId] = nil
        await writeTask?.value
        do {
            try await storage.delete(conversationId: conversationId)
        } catch {
            Logger.memberRead.error("Не удалось удалить мету прочтения \(conversationId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - События

    /// Применяет событие очереди. Ничего не ждёт: запросы и запись идут отдельными задачами.
    /// - Parameter event: событие реального времени.
    private func handle(_ event: RealtimeEvent) {
        guard !isLoggingOut else { return }
        switch event {
        case .connected:
            // События за время разрыва потеряны.
            observed.keys.forEach { refresh(conversationId: $0) }
            loadStoredConversationIdsIfNeeded()
        case let .memberRead(conversationId, userId, lastReadMessageId):
            applyEvent(conversationId: conversationId, userId: userId, lastReadMessageId: lastReadMessageId)
        case let .messageReceived(message, _, _):
            // Отправка сдвигает указатель отправителя, отдельного `memberRead` при этом нет.
            guard let currentUserId = sessionService.currentUser?.userId, message.senderId != currentUserId else { return }
            applyEvent(conversationId: message.conversationId, userId: message.senderId, lastReadMessageId: message.messageId)
        case .conversationCreated, .conversationRead, .messageEdited, .group:
            break
        }
    }

    /// Сдвигает указатель участника: в памяти — у наблюдаемой переписки, в БД — у наблюдаемой и у переписки
    /// с сохранённой метой. Мету другим перепискам событие не создаёт. Событие, не сдвинувшее указатель
    /// наблюдаемой переписки, в БД не пишется: всё, что есть в памяти, уже записано или стоит в записи.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - userId: участник.
    ///   - lastReadMessageId: новый указатель.
    private func applyEvent(conversationId: Int, userId: Int, lastReadMessageId: Int) {
        let pointers = [userId: lastReadMessageId]
        if let state = observed[conversationId] {
            guard merge(pointers, into: state, addsMembers: true, conversationId: conversationId) else { return }
            enqueueWrite(MemberReadWrite(pointers: pointers, createsMissing: true), conversationId: conversationId)
            return
        }
        guard !isStoredLoaded || storedConversationIds.contains(conversationId) else { return }
        enqueueWrite(MemberReadWrite(pointers: pointers, createsMissing: false), conversationId: conversationId)
    }

    // MARK: - Загрузка

    /// Начинает чтение переписок с сохранённой метой, если они ещё не прочитаны и чтение не идёт. После сбоя
    /// чтение повторяется при следующем `connected` или открытии экрана переписки. До `start()` ничего не делает:
    /// сессия ещё не начата.
    private func loadStoredConversationIdsIfNeeded() {
        guard subscription != nil, !isLoggingOut, !isStoredLoaded, storedIdsTask == nil else { return }
        let generation = generation
        storedIdsTask = Task { [weak self] in
            await self?.loadStoredConversationIds(generation: generation)
        }
    }

    /// Читает из БД переписки с сохранённой метой. При сбое снимает задачу чтения — следующий повод начнёт его заново.
    /// - Parameter generation: сессия, в которой начато чтение.
    private func loadStoredConversationIds(generation: Int) async {
        do {
            let ids = try await storage.fetchConversationIds()
            guard generation == self.generation else { return }
            storedConversationIds.formUnion(ids)
            isStoredLoaded = true
        } catch {
            Logger.memberRead.error("Не удалось прочитать переписки с метой прочтения: \(String(describing: error), privacy: .public)")
            guard generation == self.generation else { return }
            storedIdsTask = nil
        }
    }

    /// Читает мету переписки из БД и публикует её. Если ответ сервера уже применён, состав участников из БД
    /// не берётся: ушедшие участники вернулись бы.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - state: её состояние в памяти на момент начала наблюдения.
    ///   - generation: сессия, в которой начато чтение.
    private func loadStored(conversationId: Int, state: ConversationMemberReads, generation: Int) async {
        let stored: [Int: Int]?
        do {
            stored = try await storage.fetchPointers(conversationId: conversationId)
        } catch {
            Logger.memberRead.error("Не удалось прочитать мету прочтения \(conversationId, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        guard let stored, observed[conversationId] === state, generation == self.generation else { return }
        merge(stored, into: state, addsMembers: !state.isRefreshed, conversationId: conversationId)
    }

    /// Запрос `getMembersReadMeta`: состав участников — из ответа, указатели — максимум с известными. Ошибка
    /// логируется и отмечается в `isRefreshFailed`, показанной остаётся прежняя мета; повтор — при следующем
    /// открытии или `connected`.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - state: её состояние в памяти на момент запроса.
    ///   - generation: сессия, в которой начат запрос.
    private func performRefresh(conversationId: Int, state: ConversationMemberReads, generation: Int) async {
        let meta: [MemberReadMeta]
        do {
            meta = try await conversationService.fetchMembersReadMeta(conversationId: conversationId)
        } catch {
            guard !Task.isCancelled else { return }
            Logger.memberRead.error("Не удалось загрузить мету прочтения \(conversationId, privacy: .public): \(String(describing: error), privacy: .public)")
            state.isRefreshFailed = true
            if error.indicatesLostMembership {
                membership?.verifyMembership(conversationId: conversationId)
            }
            return
        }
        guard observed[conversationId] === state, generation == self.generation else { return }
        let response = Dictionary(meta.map { ($0.userId, $0.lastReadMessageId) }, uniquingKeysWith: max)
        var updated = response
        for (userId, pointer) in state.pointers ?? [:] where response[userId] != nil {
            updated[userId] = max(updated[userId] ?? pointer, pointer)
        }
        state.isRefreshed = true
        publish(updated, in: state, conversationId: conversationId)
        enqueueWrite(
            MemberReadWrite(pointers: response, members: Set(response.keys), createsMissing: true),
            conversationId: conversationId
        )
    }

    // MARK: - Состояние

    /// Сливает указатели с известными по максимуму.
    /// - Parameters:
    ///   - pointers: указатели по `userId`.
    ///   - state: состояние переписки.
    ///   - addsMembers: `false` — указатели участников, которых ещё нет, пропускаются.
    ///   - conversationId: переписка.
    /// - Returns: `true` — указатели изменились: участник добавлен или указатель вырос.
    @discardableResult
    private func merge(_ pointers: [Int: Int], into state: ConversationMemberReads, addsMembers: Bool, conversationId: Int) -> Bool {
        var updated = state.pointers ?? [:]
        for (userId, pointer) in pointers {
            guard addsMembers || updated[userId] != nil else { continue }
            updated[userId] = max(updated[userId] ?? pointer, pointer)
        }
        let didChange = updated != state.pointers
        publish(updated, in: state, conversationId: conversationId)
        return didChange
    }

    /// Публикует указатели и покрытие. Присваивает только изменившееся: наблюдатели не пересобираются впустую.
    /// - Parameters:
    ///   - pointers: новые указатели.
    ///   - state: состояние переписки.
    ///   - conversationId: переписка.
    private func publish(_ pointers: [Int: Int], in state: ConversationMemberReads, conversationId: Int) {
        if state.pointers != pointers {
            state.pointers = pointers
        }
        let coverage = makeCoverage(pointers, previous: state.coverage, isGroup: state.isGroup, conversationId: conversationId)
        guard coverage != state.coverage else { return }
        state.coverage = coverage
    }

    /// Покрытие прочтения: в личной переписке — всё до максимума указателей, не меньше прежнего (прочтение
    /// не отменяется); в группе — по участникам текущего состава, кроме текущего пользователя, с их временем вступления.
    /// - Parameters:
    ///   - pointers: указатели по `userId`.
    ///   - previous: прежнее покрытие.
    ///   - isGroup: групповая переписка.
    ///   - conversationId: переписка.
    /// - Returns: `nil` — указателей нет или состав группы неизвестен.
    private func makeCoverage(_ pointers: [Int: Int], previous: MessageReadCoverage?, isGroup: Bool, conversationId: Int) -> MessageReadCoverage? {
        guard isGroup else {
            let previousMax = previous?.ranges.last?.upTo ?? .min
            guard let newMax = pointers.values.max() else { return previous }
            return .single(upTo: max(newMax, previousMax))
        }
        guard let info = groupInfo?.currentInfo(conversationId: conversationId) else { return nil }
        let currentUserId = sessionService.currentUser?.userId
        let ranges = info.members.compactMap { member -> MessageReadCoverage.Range? in
            guard member.userId != currentUserId, let pointer = pointers[member.userId] else { return nil }
            return MessageReadCoverage.Range(after: member.joinedAfterMessageId, upTo: pointer)
        }
        return MessageReadCoverage(ranges)
    }

    // MARK: - Запись

    /// Ставит изменение в запись, склеивая с ждущим изменением той же переписки.
    /// - Parameters:
    ///   - write: изменение.
    ///   - conversationId: переписка.
    private func enqueueWrite(_ write: MemberReadWrite, conversationId: Int) {
        if write.createsMissing {
            storedConversationIds.insert(conversationId)
        }
        if var pending = pendingWrites[conversationId] {
            pending.merge(write)
            pendingWrites[conversationId] = pending
        } else {
            pendingWrites[conversationId] = write
        }
        guard writeTask == nil else { return }
        writeTask = Task { [weak self] in
            await self?.flushWrites()
        }
    }

    /// Пишет накопленные изменения, пока они есть: изменения, пришедшие во время записи, уходят следующей.
    private func flushWrites() async {
        while !pendingWrites.isEmpty {
            let writes = pendingWrites
            pendingWrites = [:]
            do {
                try await storage.apply(writes)
            } catch {
                Logger.memberRead.error("Не удалось сохранить мету прочтения: \(String(describing: error), privacy: .public)")
            }
        }
        writeTask = nil
    }
}

/// Прочтение одной наблюдаемой переписки. Наблюдается по отдельности: событие в одной переписке не пересобирает
/// экраны других.
@MainActor
@Observable
private final class ConversationMemberReads {
    /// Указатели по `userId`; `nil` — меты ещё нет.
    var pointers: [Int: Int]?
    /// Прочитанные хотя бы одним участником сообщения.
    var coverage: MessageReadCoverage?
    /// Групповая переписка.
    @ObservationIgnored let isGroup: Bool
    /// Последний запрос `getMembersReadMeta` не удался; сбрасывается в начале следующего.
    var isRefreshFailed = false
    /// Сколько экранов наблюдают переписку.
    @ObservationIgnored var observerCount = 1
    /// Ответ сервера уже применён: состав участников известен.
    @ObservationIgnored var isRefreshed = false
    /// Чтение из БД и первый запрос.
    @ObservationIgnored var loadTask: Task<Void, Never>?
    /// Идущий запрос `getMembersReadMeta`.
    @ObservationIgnored var refreshTask: Task<Void, Never>?

    /// - Parameter isGroup: групповая переписка.
    init(isGroup: Bool) {
        self.isGroup = isGroup
    }

    /// Отменяет чтение и запрос.
    func cancelTasks() {
        loadTask?.cancel()
        refreshTask?.cancel()
    }
}

extension Logger {
    /// Лог прочтения другими участниками: сбои, которые не показываются пользователю, но не должны теряться молча.
    static let memberRead = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "MemberRead")
}
