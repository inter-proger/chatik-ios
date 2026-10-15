//
//  SignificantTimeChangeServiceMock.swift
//  ChatikTests
//

import Foundation
import os
@testable import Chatik

/// Изменения системного времени по команде теста.
final class SignificantTimeChangeServiceMock: SignificantTimeChangeServiceProtocol, Sendable {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Void>.Continuation]())

    /// Число подписчиков, которые ещё читают поток.
    var subscriberCount: Int {
        continuations.withLock { $0.count }
    }

    /// Новый поток событий; подписчик снимается, когда перестаёт его читать.
    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [continuations] _ in
            continuations.withLock { $0[id] = nil }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    /// Сообщает всем подписчикам об изменении времени — как полночь или смена часового пояса.
    func send() {
        continuations.withLock { $0.values.forEach { $0.yield() } }
    }
}
