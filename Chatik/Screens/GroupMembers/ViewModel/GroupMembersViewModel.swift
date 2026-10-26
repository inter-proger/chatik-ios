//
//  GroupMembersViewModel.swift
//  Chatik
//

import Foundation
import Observation

/// Содержимое экрана участников: секции или заглушка.
struct GroupMembersContent: Equatable {
    /// Создатель; `nil` — его нет в составе (не должно случаться).
    let owner: GroupMemberDisplayModel?
    /// Остальные участники по имени.
    let members: [GroupMemberDisplayModel]
}

/// Участники группы: создатель и участники; создатель долгим нажатием передаёт права (`docs/group-chats.md`,
/// решение 13). Экран живой: события группы перерисовывают его через `GroupInfoService`.
@MainActor
@Observable
final class GroupMembersViewModel {
    /// Участник, которому предлагается передать права, — данные алерта подтверждения.
    private(set) var pendingTransfer: GroupMemberDisplayModel?
    /// Показан ли алерт подтверждения передачи прав.
    var isTransferConfirmationPresented = false
    /// `true`, пока идёт запрос передачи прав.
    private(set) var isChangingOwner = false

    @ObservationIgnored private let conversationId: Int
    @ObservationIgnored private let groupInfo: GroupInfoProviding
    @ObservationIgnored private let groupService: GroupServiceProtocol
    @ObservationIgnored private let membership: ConversationMembershipVerifying
    @ObservationIgnored private let sessionService: SessionServiceProtocol
    @ObservationIgnored private let userCache: UserCacheServiceProtocol
    @ObservationIgnored private let notifications: InAppNotificationServiceProtocol
    /// Пользователи, загрузка которых уже запрошена.
    @ObservationIgnored private var requestedUserIds: Set<Int> = []

    /// - Parameters:
    ///   - conversationId: группа.
    ///   - groupInfo: состав группы.
    ///   - groupService: запрос `/groups/changeOwner`.
    ///   - membership: проверка членства при `5002`.
    ///   - sessionService: текущий пользователь.
    ///   - userCache: имена и аватары участников.
    ///   - notifications: уведомления.
    init(
        conversationId: Int,
        groupInfo: GroupInfoProviding,
        groupService: GroupServiceProtocol,
        membership: ConversationMembershipVerifying,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        notifications: InAppNotificationServiceProtocol
    ) {
        self.conversationId = conversationId
        self.groupInfo = groupInfo
        self.groupService = groupService
        self.membership = membership
        self.sessionService = sessionService
        self.userCache = userCache
        self.notifications = notifications
    }

    /// Состав группы; `nil` — ещё неизвестен.
    private var info: GroupInfo? {
        groupInfo.groupInfo(conversationId: conversationId)
    }

    /// Секции экрана; `nil` — состав неизвестен (загрузка или ошибка — `isFailed`).
    var content: GroupMembersContent? {
        guard let info else { return nil }
        let currentUserId = sessionService.currentUser?.userId
        let rows = info.members.map { member in
            (member, GroupMemberDisplayModel(userId: member.userId, cachedUser: userCache.user(id: member.userId), isCurrentUser: member.userId == currentUserId))
        }
        return GroupMembersContent(
            owner: rows.first { $0.0.role == .owner }?.1,
            members: rows.filter { $0.0.role != .owner }.map(\.1).sorted(by: GroupMemberDisplayModel.isOrderedBefore)
        )
    }

    /// Последний запрос состава не удался, а показать нечего.
    var isFailed: Bool {
        info == nil && groupInfo.isRefreshFailed(conversationId: conversationId)
    }

    /// Можно ли передать права участнику: у текущего пользователя есть право, строка не его, запрос не идёт.
    /// - Parameter member: строка участника.
    func canTransferOwnership(to member: GroupMemberDisplayModel) -> Bool {
        guard !isChangingOwner, !member.isCurrentUser, let userId = sessionService.currentUser?.userId else { return false }
        return info?.member(userId: userId)?.role.canTransferOwnership ?? false
    }

    // MARK: - Действия

    /// Экран показан: состав наблюдается и обновляется.
    func didAppear() {
        groupInfo.beginObserving(conversationId: conversationId)
    }

    /// Экран скрыт.
    func didDisappear() {
        groupInfo.endObserving(conversationId: conversationId)
    }

    /// Повтор загрузки состава после ошибки.
    func didTapRetry() {
        groupInfo.refresh(conversationId: conversationId)
    }

    /// Pull-to-refresh: состав запрашивается заново, индикатор держится до ответа.
    func reload() async {
        await groupInfo.reload(conversationId: conversationId)
    }

    /// «Передать права создателя» в меню участника: алерт подтверждения.
    /// - Parameter member: будущий создатель.
    func didSelectTransferOwnership(to member: GroupMemberDisplayModel) {
        guard canTransferOwnership(to: member) else { return }
        pendingTransfer = member
        isTransferConfirmationPresented = true
    }

    /// Подтверждена передача прав: запрос; успех — новый состав и уведомление, ошибка — уведомление.
    /// - Parameter member: будущий создатель — из алерта, а не из состояния: к нажатию оно может быть сброшено.
    func didConfirmTransfer(to member: GroupMemberDisplayModel) {
        guard canTransferOwnership(to: member) else { return }
        pendingTransfer = nil
        isChangingOwner = true
        Task { await transferOwnership(to: member.id) }
    }

    /// Запрос передачи прав.
    /// - Parameter userId: будущий создатель.
    private func transferOwnership(to userId: Int) async {
        defer { isChangingOwner = false }
        do {
            let info = try await groupService.changeOwner(conversationId: conversationId, newOwnerUserId: userId)
            groupInfo.apply(info)
            notifications.showInfo(GroupMembersStrings.ownershipTransferred)
        } catch {
            if error.indicatesLostMembership {
                membership.verifyMembership(conversationId: conversationId)
            }
            notifications.showError(ErrorMessages.message(for: error))
        }
    }

    /// Запускает загрузку участников, которых ещё не запрашивали. Не загрузившиеся запрашиваются снова при
    /// следующем изменении экрана.
    func loadMissingUsers() {
        let ids = info?.members.map(\.userId) ?? []
        let newIds = ids.filter { !requestedUserIds.contains($0) && userCache.user(id: $0) == .pending }
        guard !newIds.isEmpty else { return }
        requestedUserIds.formUnion(newIds)
        Task { [weak self, userCache] in
            await userCache.loadUsers(ids: newIds)
            self?.releaseFailedUsers(newIds)
        }
    }

    /// Снимает отметку «запрошен» с пользователей, которые после загрузки не появились в кэше.
    /// - Parameter ids: пользователи завершившейся загрузки.
    private func releaseFailedUsers(_ ids: [Int]) {
        requestedUserIds.subtract(ids.filter { userCache.user(id: $0) == .pending })
    }
}
