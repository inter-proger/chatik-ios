//
//  MessagesListServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок ленты переписки: снимки публикует тест через `publish(_:)`, вызовы запоминаются.
@MainActor
final class MessagesListServiceMock: MessagesListServiceProtocol {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var synchronizeCallCount = 0
    private(set) var loadOlderCallCount = 0
    private var continuations: [AsyncStream<MessagesListSnapshot>.Continuation] = []

    /// Число подписчиков на снимки.
    var subscriberCount: Int {
        continuations.count
    }

    @MainActor
    func snapshots() async -> AsyncStream<MessagesListSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: MessagesListSnapshot.self)
        continuations.append(continuation)
        return stream
    }

    @MainActor
    func start() async {
        startCallCount += 1
    }

    @MainActor
    func synchronize() async {
        synchronizeCallCount += 1
    }

    @MainActor
    func loadOlder() async {
        loadOlderCallCount += 1
    }

    @MainActor
    func stop() async {
        stopCallCount += 1
    }

    /// Публикует снимок всем подписчикам.
    /// - Parameter snapshot: снимок.
    func publish(_ snapshot: MessagesListSnapshot) {
        continuations.forEach { $0.yield(snapshot) }
    }
}

extension MessagesListSnapshot {
    /// Снимок с заданными полями; по умолчанию — окно прочитано, без синхронизации, подгрузки и ошибки.
    static func make(
        messages: [Message] = [],
        isSyncing: Bool = false,
        isLoadingOlder: Bool = false,
        hasOlder: Bool = false,
        isLoaded: Bool = true,
        isUrgent: Bool = false,
        failure: Error? = nil
    ) -> MessagesListSnapshot {
        MessagesListSnapshot(
            messages: messages,
            isSyncing: isSyncing,
            isLoadingOlder: isLoadingOlder,
            hasOlder: hasOlder,
            isLoaded: isLoaded,
            isUrgent: isUrgent,
            failure: failure
        )
    }
}
