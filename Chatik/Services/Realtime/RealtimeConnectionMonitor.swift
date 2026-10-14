//
//  RealtimeConnectionMonitor.swift
//  Chatik
//

import Foundation
import os

/// Идентификатор WebSocket-соединения: новый на каждое подключение, дошедшее до `auth` / `connected`.
struct RealtimeConnectionId: Hashable, Sendable {
    let rawValue: UInt64
}

/// Текущее WebSocket-соединение: отмечает его `RealtimeService`, читает `MessageCacheService`.
protocol RealtimeConnectionMonitoring: Sendable {
    /// Текущее соединение; `nil` — соединения нет или оно ещё не дошло до `auth` / `connected`.
    var current: RealtimeConnectionId? { get }
    /// Соединение дошло до `auth` / `connected`: выдаёт ему новый id и делает текущим.
    @discardableResult
    func connect() -> RealtimeConnectionId
    /// Соединение закрыто. Если текущее уже другое, ничего не делает.
    func disconnect(_ id: RealtimeConnectionId)
}

/// Текущее WebSocket-соединение. Пишет `RealtimeService` — синхронно, мимо очереди событий (аренда задержала бы
/// и это); читают акторы без перехода на main, поэтому состояние под замком.
///
/// По id соединения `MessageCacheService` понимает, синхронизирована ли переписка: признак — id соединения,
/// в котором прошла синхронизация, и с закрытием соединения все признаки разом перестают совпадать с `current`.
final class RealtimeConnectionMonitor: RealtimeConnectionMonitoring {
    private struct State {
        var current: RealtimeConnectionId?
        var lastRawValue: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Текущее соединение; `nil` — соединения нет или оно ещё не дошло до `auth` / `connected`.
    var current: RealtimeConnectionId? {
        state.withLock { $0.current }
    }

    /// Соединение дошло до `auth` / `connected`: выдаёт ему новый id и делает текущим.
    /// - Returns: id соединения — чтобы закрыть именно его.
    @discardableResult
    func connect() -> RealtimeConnectionId {
        state.withLock { state in
            state.lastRawValue += 1
            let id = RealtimeConnectionId(rawValue: state.lastRawValue)
            state.current = id
            return id
        }
    }

    /// Соединение закрыто. Если текущее уже другое, ничего не делает.
    /// - Parameter id: закрытое соединение.
    func disconnect(_ id: RealtimeConnectionId) {
        state.withLock { state in
            guard state.current == id else { return }
            state.current = nil
        }
    }
}
