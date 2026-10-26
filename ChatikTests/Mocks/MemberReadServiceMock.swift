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
    /// Порог по переписке — покрытие личной переписки `(0, порог]`.
    var stubbedReadUpTo: [Int: Int] = [:]
    /// Время вступления участников по группе.
    var stubbedJoinedAfter: [Int: [Int: Int]] = [:]
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

    /// Группы среди наблюдаемых переписок.
    @ObservationIgnored private(set) var observedGroupIds: [Int] = []

    func beginObserving(conversationId: Int, isGroup: Bool) {
        beginObservingIds.append(conversationId)
        if isGroup {
            observedGroupIds.append(conversationId)
        }
    }

    func endObserving(conversationId: Int) {
        endObservingIds.append(conversationId)
    }

    func pointers(conversationId: Int) -> [Int: Int]? {
        stubbedPointers[conversationId]
    }

    func coverage(conversationId: Int) -> MessageReadCoverage? {
        stubbedReadUpTo[conversationId].map(MessageReadCoverage.single(upTo:))
    }

    func joinedAfterMessageIds(conversationId: Int) -> [Int: Int]? {
        stubbedJoinedAfter[conversationId]
    }

    /// Группы, состав которых ещё неизвестен.
    var awaitingGroupInfoIds: Set<Int> = []

    func isAwaitingGroupInfo(conversationId: Int) -> Bool {
        awaitingGroupInfoIds.contains(conversationId)
    }

    func isRefreshFailed(conversationId: Int) -> Bool {
        failedRefreshIds.contains(conversationId)
    }

    func refresh(conversationId: Int) {
        refreshIds.append(conversationId)
    }
}

extension MemberReadServiceMock {
    func conversationWasRemoved(_ info: RemovedConversationInfo) async {}

    func groupInfoDidChange(_ info: GroupInfo, isAuthoritative: Bool) {}
}
