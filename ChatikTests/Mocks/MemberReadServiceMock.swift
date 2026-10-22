//
//  MemberReadServiceMock.swift
//  ChatikTests
//

import Foundation
import Observation
@testable import Chatik

/// Мок прочтения другими участниками: отдаёт заданные указатели и порог и запоминает вызовы. Наблюдается, как
/// настоящий сервис: смена `stubbedReadUpTo` пересобирает ленту.
@MainActor
@Observable
final class MemberReadServiceMock: MemberReadServiceProtocol {
    /// Указатели по переписке.
    var stubbedPointers: [Int: [Int: Int]] = [:]
    /// Порог по переписке.
    var stubbedReadUpTo: [Int: Int] = [:]
    /// Переписки, у которых последний запрос указателей не удался.
    var failedRefreshIds: Set<Int> = []
    @ObservationIgnored private(set) var startCount = 0
    @ObservationIgnored private(set) var beginObservingIds: [Int] = []
    @ObservationIgnored private(set) var endObservingIds: [Int] = []
    @ObservationIgnored private(set) var refreshIds: [Int] = []
    /// Вызывается в `start()`.
    @ObservationIgnored var onStart: (() -> Void)?

    func start() {
        startCount += 1
        onStart?()
    }

    func beginObserving(conversationId: Int) {
        beginObservingIds.append(conversationId)
    }

    func endObserving(conversationId: Int) {
        endObservingIds.append(conversationId)
    }

    func pointers(conversationId: Int) -> [Int: Int]? {
        stubbedPointers[conversationId]
    }

    func readUpTo(conversationId: Int) -> Int? {
        stubbedReadUpTo[conversationId]
    }

    func isRefreshFailed(conversationId: Int) -> Bool {
        failedRefreshIds.contains(conversationId)
    }

    func refresh(conversationId: Int) {
        refreshIds.append(conversationId)
    }
}
