//
//  RealtimeEventQueueMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок очереди событий: события доставляет тест через `send(_:)` (дожидаясь обработчиков), аренды запоминаются.
@MainActor
final class RealtimeEventQueueMock: RealtimeEventQueueProtocol {
    private var handlers: [UUID: @MainActor (RealtimeEvent) async -> Void] = [:]
    private var leases: [UUID: StaticString] = [:]
    private var leaseIds: [ObjectIdentifier: UUID] = [:]
    /// События, положенные в очередь через `enqueue`.
    private(set) var enqueued: [RealtimeEvent] = []
    /// Причины всех взятых аренд по порядку.
    private(set) var leaseReasons: [StaticString] = []
    /// Взятые аренды — чтобы тест мог снять их принудительно.
    private(set) var issuedLeases: [RealtimeQueueLease] = []

    /// Число подписчиков.
    var subscriberCount: Int {
        handlers.count
    }

    /// Число активных аренд.
    var activeLeaseCount: Int {
        leases.count
    }

    func enqueue(_ event: RealtimeEvent) {
        enqueued.append(event)
    }

    func subscribe(_ handler: @escaping @MainActor (RealtimeEvent) async -> Void) -> RealtimeSubscription {
        let id = UUID()
        handlers[id] = handler
        return RealtimeSubscription(
            id: id,
            onCancel: { [weak self] id in self?.handlers[id] = nil },
            onDeinit: { [mock = self] id in Task { @MainActor in mock.handlers[id] = nil } }
        )
    }

    func suspendProcessing(reason: StaticString) -> RealtimeQueueLease {
        let id = UUID()
        leases[id] = reason
        leaseReasons.append(reason)
        let lease = RealtimeQueueLease(
            id: id,
            onRelease: { [weak self] id in self?.leases[id] = nil },
            onDeinit: { [mock = self] id in Task { @MainActor in mock.leases[id] = nil } }
        )
        issuedLeases.append(lease)
        leaseIds[ObjectIdentifier(lease)] = id
        return lease
    }

    /// Доставляет событие всем подписчикам и дожидается их — без учёта аренд.
    /// - Parameter event: событие реального времени.
    func send(_ event: RealtimeEvent) async {
        for handler in handlers.values {
            await handler(event)
        }
    }

    /// Снимает аренду принудительно, как сторожевой таймаут.
    /// - Parameter lease: аренда.
    func expire(_ lease: RealtimeQueueLease) {
        lease.expire()
        leaseIds[ObjectIdentifier(lease)].map { leases[$0] = nil }
    }
}
