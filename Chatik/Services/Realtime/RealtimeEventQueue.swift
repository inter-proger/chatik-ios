//
//  RealtimeEventQueue.swift
//  Chatik
//

import Foundation
import os

@MainActor
protocol RealtimeEventQueueProtocol: AuthServiceObserver, Sendable {
    /// Кладёт событие в конец очереди; доставка начнётся, если нет аренд.
    func enqueue(_ event: RealtimeEvent)
    /// Подписывает обработчик. Очередь ждёт каждый обработчик, прежде чем взять следующее событие.
    /// Подписка живёт, пока жив возвращённый токен (или до его `cancel()`).
    func subscribe(_ handler: @escaping @MainActor (RealtimeEvent) async -> Void) -> RealtimeSubscription
    /// Аренда для случаев, когда приостановка начинается и заканчивается в разных местах: например, захватывается
    /// синхронно в обработчике события, а снимается задачей, которая продолжает работу.
    func suspendProcessing(reason: StaticString) -> RealtimeQueueLease
}

extension RealtimeEventQueueProtocol {
    /// Приостанавливает обработку событий на время `operation`; аренда снимается при любом исходе — возврате,
    /// ошибке и отмене задачи.
    /// - Parameters:
    ///   - reason: кто и зачем приостановил очередь — для лога сторожевого таймаута.
    ///   - operation: работа под арендой; получает аренду, чтобы проверить `isExpired` перед применением результата.
    func withProcessingSuspended<T>(
        reason: StaticString,
        _ operation: (RealtimeQueueLease) async throws -> T
    ) async rethrows -> T {
        let lease = suspendProcessing(reason: reason)
        defer { lease.release() }
        return try await operation(lease)
    }

    /// Подписывает обработчик на время вызывающей задачи: возвращается, когда задачу отменят, и тогда же отписывает.
    /// - Parameter handler: обработчик событий.
    func observe(_ handler: @escaping @MainActor (RealtimeEvent) async -> Void) async {
        let subscription = subscribe(handler)
        defer { subscription.cancel() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}

/// Аренда очереди событий: пока жива хотя бы одна аренда, события только копятся.
@MainActor
final class RealtimeQueueLease {
    /// Аренду сняли принудительно (сторожевой таймаут или выход из аккаунта): очередь уже доставила накопленные
    /// события, и результат операции старее них — заменять им состояние нельзя.
    private(set) var isExpired = false
    private var isReleased = false
    private let id: UUID
    private let onRelease: @MainActor (UUID) -> Void
    private let onDeinit: @Sendable (UUID) -> Void

    /// - Parameters:
    ///   - id: идентификатор аренды в очереди.
    ///   - onRelease: снимает аренду в очереди.
    ///   - onDeinit: снимает аренду, если объект потеряли без `release()`. Вызывается из неизолированного `deinit`
    ///     (`isolated deinit` требует iOS 18.4+), поэтому `Sendable` и снимает аренду асинхронно.
    init(id: UUID, onRelease: @escaping @MainActor (UUID) -> Void, onDeinit: @escaping @Sendable (UUID) -> Void) {
        self.id = id
        self.onRelease = onRelease
        self.onDeinit = onDeinit
    }

    /// Снимает аренду. Идемпотентно: повторный вызов и вызов после принудительного снятия ничего не делают.
    func release() {
        guard !isReleased else { return }
        isReleased = true
        onRelease(id)
    }

    /// Отмечает аренду снятой принудительно; вызывает очередь.
    func expire() {
        isExpired = true
        isReleased = true
    }

    deinit {
        onDeinit(id)
    }
}

/// Подписка на очередь событий: обработчик отписывается при `cancel()` или уничтожении токена.
@MainActor
final class RealtimeSubscription {
    private let id: UUID
    private let onCancel: @MainActor (UUID) -> Void
    private let onDeinit: @Sendable (UUID) -> Void

    /// - Parameters:
    ///   - id: идентификатор подписки в очереди.
    ///   - onCancel: отписывает обработчик.
    ///   - onDeinit: отписывает обработчик при уничтожении токена; вызывается из неизолированного `deinit`.
    init(id: UUID, onCancel: @escaping @MainActor (UUID) -> Void, onDeinit: @escaping @Sendable (UUID) -> Void) {
        self.id = id
        self.onCancel = onCancel
        self.onDeinit = onDeinit
    }

    /// Отписывает обработчик. Идемпотентно.
    func cancel() {
        onCancel(id)
    }

    deinit {
        onDeinit(id)
    }
}

/// Очередь событий WebSocket между `RealtimeService` и всеми потребителями (список чатов, экран переписки,
/// очередь отправки). Одна на приложение, чтобы все потребители видели события в одном порядке.
///
/// События доставляются по одному в порядке прихода: очередь ждёт каждый обработчик, прежде чем взять следующее
/// событие. Обработку можно приостановить арендой (семафор со счётчиком): пока есть хотя бы одна аренда, события
/// копятся и применяются после снятия последней. Аренда проверяется перед каждым событием, поэтому аренда, взятая
/// во время обработки, останавливает доставку со следующего события.
///
/// Событие доставляется только текущим подписчикам и не хранится для будущих: подписаться нужно до того,
/// как события пойдут.
///
/// Гарантии, что семафор откроется: scoped-API `withProcessingSuspended`, снятие в `deinit` аренды, сторожевой
/// таймаут и сброс всех аренд при выходе из аккаунта.
@MainActor
final class RealtimeEventQueue: RealtimeEventQueueProtocol {
    /// Сколько аренда может держать очередь, прежде чем её снимут принудительно. Запросы под арендой ограничены
    /// таймаутом простоя `AppConfig.requestTimeout`, поэтому сторожу нужен запас.
    nonisolated static let defaultLeaseTimeout: Duration = .seconds(90)

    private struct Subscriber {
        let id: UUID
        let handler: @MainActor (RealtimeEvent) async -> Void
    }

    private struct LeaseInfo {
        let reason: StaticString
        weak var lease: RealtimeQueueLease?
        let watchdog: Task<Void, Never>
    }

    /// События, ждущие доставки; доставленные — до `pendingHead`. Массив сжимается, когда голова уходит дальше
    /// половины.
    private var pending: [RealtimeEvent] = []
    private var pendingHead = 0
    private var subscribers: [Subscriber] = []
    /// Активные аренды; очередь держит их по id, а не сильной ссылкой.
    private var activeLeases: [UUID: LeaseInfo] = [:]
    private var drainTask: Task<Void, Never>?
    private let leaseTimeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onLeaseTimeout: (StaticString) -> Void

    /// - Parameters:
    ///   - leaseTimeout: сторожевой таймаут аренды.
    ///   - sleep: ожидание; подменяется в тестах.
    ///   - onLeaseTimeout: реакция на сработавший сторожевой таймаут; в Debug — `assertionFailure`, это ошибка
    ///     в коде. Подменяется в тестах.
    init(
        leaseTimeout: Duration = defaultLeaseTimeout,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onLeaseTimeout: @escaping (StaticString) -> Void = { reason in
            assertionFailure("Аренда очереди событий не снята за отведённое время: \(reason)")
        }
    ) {
        self.leaseTimeout = leaseTimeout
        self.sleep = sleep
        self.onLeaseTimeout = onLeaseTimeout
    }

    /// Число активных аренд.
    var activeLeaseCount: Int {
        activeLeases.count
    }

    /// Кладёт событие в конец очереди и запускает доставку, если она не идёт и нет аренд.
    /// - Parameter event: событие реального времени.
    func enqueue(_ event: RealtimeEvent) {
        pending.append(event)
        startDrainIfNeeded()
    }

    /// Подписывает обработчик; он получает события, положенные в очередь после подписки и ещё не доставленные.
    /// - Parameter handler: обработчик; очередь ждёт его, прежде чем взять следующее событие.
    func subscribe(_ handler: @escaping @MainActor (RealtimeEvent) async -> Void) -> RealtimeSubscription {
        let id = UUID()
        subscribers.append(Subscriber(id: id, handler: handler))
        return RealtimeSubscription(
            id: id,
            onCancel: { [weak self] id in self?.unsubscribe(id) },
            onDeinit: { [queue = self] id in Task { @MainActor in queue.unsubscribe(id) } }
        )
    }

    /// Берёт аренду и запускает её сторожевой таймаут.
    /// - Parameter reason: кто и зачем приостановил очередь — для лога сторожевого таймаута.
    func suspendProcessing(reason: StaticString) -> RealtimeQueueLease {
        let id = UUID()
        let lease = RealtimeQueueLease(
            id: id,
            onRelease: { [weak self] id in self?.releaseLease(id) },
            onDeinit: { [queue = self] id in Task { @MainActor in queue.releaseLease(id) } }
        )
        let watchdog = Task { [weak self, sleep, leaseTimeout] in
            guard (try? await sleep(leaseTimeout)) != nil, !Task.isCancelled else { return }
            self?.expireLease(id)
        }
        activeLeases[id] = LeaseInfo(reason: reason, lease: lease, watchdog: watchdog)
        return lease
    }

    // MARK: - Выход из аккаунта

    /// Выход из аккаунта начинается (`AuthServiceObserver`): накопленные события отбрасываются, все аренды
    /// снимаются принудительно, а идущая доставка отменяется и дожидается — только ждать нельзя: обработчик может
    /// висеть на сетевом запросе до таймаута.
    func authServiceWillLogout() async {
        pending.removeAll()
        pendingHead = 0
        for info in activeLeases.values {
            info.watchdog.cancel()
            info.lease?.expire()
        }
        activeLeases.removeAll()
        let drainTask = drainTask
        drainTask?.cancel()
        await drainTask?.value
    }

    // MARK: - Доставка

    /// Запускает доставку, если она не идёт, аренд нет и есть что доставлять.
    private func startDrainIfNeeded() {
        guard drainTask == nil, activeLeases.isEmpty, pendingHead < pending.count else { return }
        drainTask = Task { await drain() }
    }

    /// Доставляет события по одному, пока очередь не опустеет, не появится аренда или задачу не отменят.
    /// Перед каждым событием проверяются аренды: аренда, взятая обработчиком, останавливает доставку со следующего.
    private func drain() async {
        while activeLeases.isEmpty, !Task.isCancelled, let event = popFirst() {
            for subscriber in subscribers {
                guard !Task.isCancelled else { break }
                // Обработчик, отписавшийся во время доставки этого события, его уже не получает.
                guard subscribers.contains(where: { $0.id == subscriber.id }) else { continue }
                await subscriber.handler(event)
            }
        }
        drainTask = nil
    }

    /// Достаёт первое недоставленное событие.
    private func popFirst() -> RealtimeEvent? {
        guard pendingHead < pending.count else { return nil }
        let event = pending[pendingHead]
        pendingHead += 1
        if pendingHead * 2 >= pending.count {
            pending.removeFirst(pendingHead)
            pendingHead = 0
        }
        return event
    }

    /// Отписывает обработчик. Идемпотентно.
    /// - Parameter id: идентификатор подписки.
    private func unsubscribe(_ id: UUID) {
        subscribers.removeAll { $0.id == id }
    }

    // MARK: - Аренды

    /// Снимает аренду; снятие последней запускает доставку накопленных событий. Аренду, которой уже нет
    /// (снята повторно, принудительно или при выходе), игнорирует.
    /// - Parameter id: идентификатор аренды.
    private func releaseLease(_ id: UUID) {
        guard let info = activeLeases.removeValue(forKey: id) else { return }
        info.watchdog.cancel()
        startDrainIfNeeded()
    }

    /// Снимает аренду принудительно по сторожевому таймауту: аренду забыли снять — это ошибка в коде.
    /// - Parameter id: идентификатор аренды.
    private func expireLease(_ id: UUID) {
        guard let info = activeLeases.removeValue(forKey: id) else { return }
        info.lease?.expire()
        Logger.realtime.fault("Аренда очереди событий снята по таймауту: \(String(describing: info.reason), privacy: .public)")
        onLeaseTimeout(info.reason)
        startDrainIfNeeded()
    }
}
