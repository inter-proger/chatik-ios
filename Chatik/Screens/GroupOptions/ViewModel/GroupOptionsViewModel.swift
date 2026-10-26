//
//  GroupOptionsViewModel.swift
//  Chatik
//

import Foundation
import Observation

/// Опции группы: аватар, название и описание (только просмотр), число участников, добавление участников и выход
/// (`docs/group-chats.md`, решение 12).
@MainActor
@Observable
final class GroupOptionsViewModel {
    /// Показан ли алерт подтверждения выхода.
    var isLeaveConfirmationPresented = false
    /// `true`, пока идёт запрос выхода: все действия и уход с экрана заблокированы.
    private(set) var isLeaving = false

    @ObservationIgnored private let snapshot: Conversation
    @ObservationIgnored private let conversationList: ConversationListServiceProtocol
    @ObservationIgnored private let groupInfo: GroupInfoProviding
    @ObservationIgnored private let groupService: GroupServiceProtocol
    @ObservationIgnored private let sessionService: SessionServiceProtocol
    @ObservationIgnored private let notifications: InAppNotificationServiceProtocol
    @ObservationIgnored private let navigator: GroupNavigating

    /// - Parameters:
    ///   - conversation: группа — снимок с экрана переписки; запасной источник, если её нет в списке.
    ///   - conversationList: список переписок — живая версия группы и применение выхода.
    ///   - groupInfo: состав группы.
    ///   - groupService: запрос `/groups/leave`.
    ///   - sessionService: текущий пользователь — его роль.
    ///   - notifications: уведомления о выходе и ошибках.
    ///   - navigator: переходы к экранам группы и к списку.
    init(
        conversation: Conversation,
        conversationList: ConversationListServiceProtocol,
        groupInfo: GroupInfoProviding,
        groupService: GroupServiceProtocol,
        sessionService: SessionServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        navigator: GroupNavigating
    ) {
        snapshot = conversation
        self.conversationList = conversationList
        self.groupInfo = groupInfo
        self.groupService = groupService
        self.sessionService = sessionService
        self.notifications = notifications
        self.navigator = navigator
    }

    private var conversationId: Int {
        snapshot.conversationId
    }

    /// Группа: из списка, а если её там нет (открыта из уведомления, хвост списка инвалидирован), — снимок.
    var conversation: Conversation {
        conversationList.conversation(id: conversationId) ?? snapshot
    }

    /// Состав группы; `nil` — ещё неизвестен.
    var info: GroupInfo? {
        groupInfo.groupInfo(conversationId: conversationId)
    }

    /// Название группы для шапки.
    var title: String {
        conversation.name ?? GroupOptionsStrings.untitled
    }

    /// Число участников; `nil` — состав неизвестен, вместо числа индикатор.
    var membersCount: Int? {
        info?.members.count
    }

    /// Роль текущего пользователя; `nil` — состав неизвестен.
    private var currentRole: GroupRole? {
        guard let userId = sessionService.currentUser?.userId else { return nil }
        return info?.member(userId: userId)?.role
    }

    /// Показывать ли «Добавить участников»: только тем, у кого есть право добавлять.
    var canAddMembers: Bool {
        currentRole?.canAddMembers ?? false
    }

    /// Активна ли «Покинуть группу»: без состава нельзя выбрать текст предупреждения.
    var isLeaveEnabled: Bool {
        info != nil && !isLeaving
    }

    /// Текст алерта выхода по случаю: участник, владелец с другими участниками, единственный участник.
    var leaveMessage: String {
        guard let info, let role = currentRole else { return GroupOptionsStrings.leaveMessage }
        guard info.members.count > 1 else { return GroupOptionsStrings.leaveMessageLastMember }
        guard role == .owner else { return GroupOptionsStrings.leaveMessage }
        return GroupOptionsStrings.leaveMessageOwner
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

    /// «Участники»: экран участников.
    func didTapMembers() {
        guard !isLeaving else { return }
        navigator.showGroupMembers(conversationId: conversationId)
    }

    /// «Добавить участников»: экран добавления.
    func didTapAddMembers() {
        guard !isLeaving, canAddMembers else { return }
        navigator.showAddGroupMembers(conversationId: conversationId)
    }

    /// «Покинуть группу»: алерт подтверждения.
    func didTapLeave() {
        guard isLeaveEnabled else { return }
        isLeaveConfirmationPresented = true
    }

    /// Подтверждён выход: запрос, затем список чатов и уведомление; ошибка — уведомление, экран разблокируется.
    func didConfirmLeave() {
        guard isLeaveEnabled else { return }
        isLeaving = true
        Task { await leave() }
    }

    /// Запрос выхода. Пока он идёт, удаление группы с любой стороны считается своим выходом.
    private func leave() async {
        conversationList.beginLeaving(conversationId: conversationId)
        defer {
            conversationList.endLeaving(conversationId: conversationId)
            isLeaving = false
        }
        do {
            let removal = try await groupService.leave(conversationId: conversationId)
            conversationList.applyLeave(removal)
            navigator.popToRoot()
            notifications.showInfo(GroupOptionsStrings.left)
        } catch {
            // `5002`: пользователь уже не участник — об этом сообщит проверка членства, второе уведомление не нужно.
            guard error.indicatesLostMembership else {
                notifications.showError(ErrorMessages.message(for: error))
                return
            }
            conversationList.verifyMembership(conversationId: conversationId)
        }
    }
}
