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

/// Действие с участником в меню по долгому нажатию (`docs/group-chats.md`, решение 18).
enum GroupMemberAction: Hashable {
    /// Создать (или найти) личную переписку с участником и открыть её.
    case directChat
    /// Передать участнику права создателя.
    case transferOwnership
    /// Исключить участника из группы.
    case remove
}

/// Участники группы: создатель и участники; меню участника — личный диалог, а у создателя ещё передача прав
/// и исключение (`docs/group-chats.md`, решения 13, 18–20). Экран живой: события группы перерисовывают его через
/// `GroupInfoService`.
@MainActor
@Observable
final class GroupMembersViewModel {
    /// Участник, которому предлагается передать права, — данные алерта подтверждения.
    private(set) var pendingTransfer: GroupMemberDisplayModel?
    /// Показан ли алерт подтверждения передачи прав; пишет и привязка алерта.
    var isTransferConfirmationPresented = false
    /// Участник, которого предлагается исключить, — данные алерта подтверждения.
    private(set) var pendingRemoval: GroupMemberDisplayModel?
    /// Показан ли алерт подтверждения исключения; пишет и привязка алерта.
    var isRemoveConfirmationPresented = false
    /// `true`, пока идёт запрос с экрана (передача прав, исключение, личный диалог): меню не показывается.
    private(set) var isPerformingAction = false
    /// Участник, личный диалог с которым создаётся, — в его строке индикатор; `nil` — запроса нет.
    private(set) var openingChatMemberId: Int?

    @ObservationIgnored private let conversationId: Int
    @ObservationIgnored private let groupInfo: GroupInfoProviding
    @ObservationIgnored private let groupService: GroupServiceProtocol
    @ObservationIgnored private let conversationService: ConversationServiceProtocol
    @ObservationIgnored private let conversationList: ConversationApplying & ConversationMembershipVerifying
    @ObservationIgnored let sessionService: SessionServiceProtocol
    @ObservationIgnored private let userCache: UserCacheServiceProtocol
    @ObservationIgnored private let notifications: InAppNotificationServiceProtocol
    @ObservationIgnored private let navigator: GroupNavigating
    /// Пользователи, загрузка которых уже запрошена.
    @ObservationIgnored private var requestedUserIds: Set<Int> = []
    /// Создание личного диалога; отменяется при уходе с экрана, чтобы поздний ответ не открыл переписку.
    @ObservationIgnored private var directChatTask: Task<Void, Never>?

    /// - Parameters:
    ///   - conversationId: группа.
    ///   - groupInfo: состав группы.
    ///   - groupService: `/groups/changeOwner` и `/groups/removeMembers`.
    ///   - conversationService: `/conversations/createSingle` — личный диалог.
    ///   - conversationList: список переписок — личный диалог в список и проверка членства при `5002`.
    ///   - sessionService: текущий пользователь.
    ///   - userCache: имена и аватары участников.
    ///   - notifications: уведомления.
    ///   - navigator: открытие личного диалога.
    init(
        conversationId: Int,
        groupInfo: GroupInfoProviding,
        groupService: GroupServiceProtocol,
        conversationService: ConversationServiceProtocol,
        conversationList: ConversationApplying & ConversationMembershipVerifying,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        navigator: GroupNavigating
    ) {
        self.conversationId = conversationId
        self.groupInfo = groupInfo
        self.groupService = groupService
        self.conversationService = conversationService
        self.conversationList = conversationList
        self.sessionService = sessionService
        self.userCache = userCache
        self.notifications = notifications
        self.navigator = navigator
    }

    /// Состав группы; `nil` — ещё неизвестен.
    var info: GroupInfo? {
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

    // MARK: - Действия

    /// Экран показан: состав наблюдается и обновляется.
    func didAppear() {
        groupInfo.beginObserving(conversationId: conversationId)
    }

    /// Экран скрыт: наблюдение снимается, создание личного диалога отменяется.
    func didDisappear() {
        groupInfo.endObserving(conversationId: conversationId)
        directChatTask?.cancel()
    }

    /// Повтор загрузки состава после ошибки.
    func didTapRetry() {
        groupInfo.refresh(conversationId: conversationId)
    }

    /// Pull-to-refresh: состав запрашивается заново, индикатор держится до ответа.
    func reload() async {
        await groupInfo.reload(conversationId: conversationId)
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

    /// Выбран пункт меню участника.
    /// - Parameters:
    ///   - action: действие.
    ///   - member: участник.
    func didSelect(_ action: GroupMemberAction, for member: GroupMemberDisplayModel) {
        guard actions(for: member).contains(action) else { return }
        switch action {
        case .directChat:
            openDirectChat(with: member)
        case .transferOwnership:
            pendingTransfer = member
            isTransferConfirmationPresented = true
        case .remove:
            pendingRemoval = member
            isRemoveConfirmationPresented = true
        }
    }

    /// Подтверждена передача прав: запрос; успех — новый состав и уведомление, ошибка — уведомление.
    /// - Parameter member: будущий создатель — из алерта, а не из состояния: к нажатию оно может быть сброшено.
    func didConfirmTransfer(to member: GroupMemberDisplayModel) {
        guard canConfirm(.transferOwnership, for: member) else { return }
        pendingTransfer = nil
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                let info = try await groupService.changeOwner(conversationId: conversationId, newOwnerUserId: member.id)
                groupInfo.apply(info)
                notifications.showInfo(GroupMembersStrings.ownershipTransferred)
            } catch {
                handleGroupError(error)
            }
        }
    }

    /// Подтверждено исключение: запрос; новый состав применяется и при отказе по участнику.
    /// - Parameter member: исключаемый — из алерта, а не из состояния: к нажатию оно может быть сброшено.
    func didConfirmRemoval(of member: GroupMemberDisplayModel) {
        guard canConfirm(.remove, for: member) else { return }
        pendingRemoval = nil
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                let result = try await groupService.removeMembers(conversationId: conversationId, userIds: [member.id])
                groupInfo.apply(result.groupInfo)
                showRemovalResult(result)
            } catch {
                handleGroupError(error)
            }
        }
    }

    // MARK: - Приватное

    /// Снимает отметку «запрошен» с пользователей, которые после загрузки не появились в кэше.
    /// - Parameter ids: пользователи завершившейся загрузки.
    private func releaseFailedUsers(_ ids: [Int]) {
        requestedUserIds.subtract(ids.filter { userCache.user(id: $0) == .pending })
    }

    /// Создаёт личную переписку (сервер вернёт существующую, если она уже есть), кладёт её в список и открывает
    /// вместо стека экранов. После ухода с экрана переписка только попадает в список, но не открывается.
    /// - Parameter member: собеседник.
    private func openDirectChat(with member: GroupMemberDisplayModel) {
        isPerformingAction = true
        openingChatMemberId = member.id
        directChatTask = Task {
            defer {
                isPerformingAction = false
                openingChatMemberId = nil
            }
            do {
                let conversation = try await conversationService.createSingle(userId: member.id)
                conversationList.apply(conversation)
                guard !Task.isCancelled else { return }
                navigator.openConversation(conversation)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                notifications.showError(ErrorMessages.message(for: error))
            }
        }
    }

    /// Можно ли выполнить подтверждённое в алерте действие. Пока алерт был открыт, право могло пропасть (права
    /// переданы с другого устройства) — тогда показывается ошибка, а не молчаливый отказ.
    /// - Parameters:
    ///   - action: подтверждённое действие.
    ///   - member: участник из алерта.
    private func canConfirm(_ action: GroupMemberAction, for member: GroupMemberDisplayModel) -> Bool {
        guard !isPerformingAction else { return false }
        guard actions(for: member).contains(action) else {
            notifications.showError(CommonStrings.errorGroupOwnerOnly)
            return false
        }
        return true
    }

    /// Уведомление по итогу исключения: успех или причина отказа (`5007` — уже не участник, `5008` — владелец).
    /// - Parameter result: ответ `removeMembers`.
    private func showRemovalResult(_ result: RemoveMembersResult) {
        guard let failure = result.notRemovedUsersInfo.first else {
            notifications.showInfo(GroupMembersStrings.memberRemoved)
            return
        }
        notifications.showError(ErrorMessages.message(for: NetworkError.api(code: failure.errorCode)))
    }

    /// Ошибка действия владельца: `5002` — проверка членства без отдельного уведомления (о потере доступа сообщит
    /// она), `5004` — права уже нет: состав обновляется; остальное — уведомление.
    /// - Parameter error: ошибка запроса.
    private func handleGroupError(_ error: Error) {
        guard !error.indicatesLostMembership else {
            conversationList.verifyMembership(conversationId: conversationId)
            return
        }
        if case NetworkError.api(code: NetworkError.Code.groupOwnerOnly) = error {
            groupInfo.refresh(conversationId: conversationId)
        }
        notifications.showError(ErrorMessages.message(for: error))
    }
}
