//
//  GroupInfoServiceMock.swift
//  ChatikTests
//

import Foundation
import Observation
@testable import Chatik

/// Мок состава групп: составы задаёт тест, вызовы запоминаются. Наблюдается, как настоящий сервис.
@MainActor
@Observable
final class GroupInfoServiceMock: GroupInfoServiceProtocol {
    /// Составы по группе.
    var infos: [Int: GroupInfo] = [:]
    /// Группы, у которых последний запрос не удался.
    var failedRefreshIds: Set<Int> = []
    /// Чем отвечает `snapshot`, если состава нет в `infos`.
    @ObservationIgnored var stubbedSnapshotError: Error = NetworkError.api(code: NetworkError.Code.conversationNotFound)
    @ObservationIgnored private(set) var startCount = 0
    @ObservationIgnored private(set) var beginObservingIds: [Int] = []
    @ObservationIgnored private(set) var endObservingIds: [Int] = []
    @ObservationIgnored private(set) var refreshIds: [Int] = []
    @ObservationIgnored private(set) var snapshotIds: [Int] = []
    @ObservationIgnored private(set) var applied: [GroupInfo] = []
    /// Вызывается в `start()`.
    @ObservationIgnored var onStart: (() -> Void)?

    func start() {
        startCount += 1
        onStart?()
    }

    func addObserver(_ observer: GroupInfoObserver) {}

    func beginObserving(conversationId: Int) {
        beginObservingIds.append(conversationId)
    }

    func endObserving(conversationId: Int) {
        endObservingIds.append(conversationId)
    }

    func groupInfo(conversationId: Int) -> GroupInfo? {
        infos[conversationId]
    }

    func isRefreshFailed(conversationId: Int) -> Bool {
        failedRefreshIds.contains(conversationId)
    }

    func refresh(conversationId: Int) {
        refreshIds.append(conversationId)
    }

    func reload(conversationId: Int) async {
        refreshIds.append(conversationId)
    }

    func snapshot(conversationId: Int) async throws -> GroupInfo {
        snapshotIds.append(conversationId)
        guard let info = infos[conversationId] else { throw stubbedSnapshotError }
        return info
    }

    func currentInfo(conversationId: Int) -> GroupInfo? {
        infos[conversationId]
    }

    func apply(_ info: GroupInfo) {
        applied.append(info)
        guard info.version > infos[info.conversationId]?.version ?? .min else { return }
        infos[info.conversationId] = info
    }

    func conversationWasRemoved(_ info: RemovedConversationInfo) async {}
}
