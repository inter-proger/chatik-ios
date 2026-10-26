//
//  GroupService.swift
//  Chatik
//

import Foundation

protocol GroupServiceProtocol {
    /// Создаёт группу; текущий пользователь становится владельцем.
    func create(name: String, description: String?, avatarFileId: Int?) async throws -> CreatedGroup
    /// Добавляет пользователей в группу; кого добавить нельзя — в `notAddedUsersInfo`, это не ошибка.
    func addMembers(conversationId: Int, userIds: [Int]) async throws -> AddMembersResult
    /// Исключает участников из группы; кого исключить нельзя — в `notRemovedUsersInfo`, это не ошибка.
    func removeMembers(conversationId: Int, userIds: [Int]) async throws -> RemoveMembersResult
    /// Передаёт владение участнику группы.
    func changeOwner(conversationId: Int, newOwnerUserId: Int) async throws -> GroupInfo
    /// Возвращает состав и роли группы.
    func fetchInfo(conversationId: Int) async throws -> GroupInfo
    /// Выход текущего пользователя из группы.
    func leave(conversationId: Int) async throws -> ConversationRemoval
}

/// Запросы `/groups/*`. Action `users` из ответов исполняет сетевой слой.
final class GroupService: GroupServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Создаёт группу через `POST /groups/create`. Не идемпотентен: повтор создаст вторую группу.
    /// - Parameters:
    ///   - name: название, уже обрезанное (1…128 кодовых точек), иначе ошибка 1003.
    ///   - description: описание, уже обрезанное (до 1024); `nil` — без описания.
    ///   - avatarFileId: загруженное текущим пользователем изображение; `nil` — без аватара.
    /// - Returns: созданная группа и её состав.
    func create(name: String, description: String?, avatarFileId: Int?) async throws -> CreatedGroup {
        try await networkService.request(GroupEndpoint.create(name: name, description: description, avatarFileId: avatarFileId))
    }

    /// Добавляет участников через `POST /groups/addMembers`. Только владелец (иначе 5004).
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - userIds: пользователи, от 1 до 100.
    /// - Returns: добавленные, не добавленные с причиной и состав после изменения.
    func addMembers(conversationId: Int, userIds: [Int]) async throws -> AddMembersResult {
        try await networkService.request(GroupEndpoint.addMembers(conversationId: conversationId, userIds: userIds))
    }

    /// Исключает участников через `POST /groups/removeMembers`. Только владелец (иначе 5004). Исключённый сразу теряет
    /// доступ к группе, его сообщения остаются.
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - userIds: участники, от 1 до 100.
    /// - Returns: исключённые, не исключённые с причиной и состав после изменения.
    func removeMembers(conversationId: Int, userIds: [Int]) async throws -> RemoveMembersResult {
        try await networkService.request(GroupEndpoint.removeMembers(conversationId: conversationId, userIds: userIds))
    }

    /// Передаёт владение через `POST /groups/changeOwner`. Только владелец (иначе 5004).
    /// - Parameters:
    ///   - conversationId: группа.
    ///   - newOwnerUserId: участник группы, не текущий владелец.
    /// - Returns: состав после изменения.
    func changeOwner(conversationId: Int, newOwnerUserId: Int) async throws -> GroupInfo {
        let response: GroupInfoResponse = try await networkService.request(
            GroupEndpoint.changeOwner(conversationId: conversationId, newOwnerUserId: newOwnerUserId)
        )
        return response.groupInfo
    }

    /// Загружает состав группы через `GET /groups/getInfo`.
    /// - Parameter conversationId: группа; не участник — ошибка 5002.
    func fetchInfo(conversationId: Int) async throws -> GroupInfo {
        let response: GroupInfoResponse = try await networkService.request(GroupEndpoint.getInfo(conversationId: conversationId))
        return response.groupInfo
    }

    /// Выходит из группы через `POST /groups/leave`. Если выходит владелец, владельцем становится вступивший
    /// раньше всех.
    /// - Parameter conversationId: группа.
    /// - Returns: метка выхода и общий счётчик непрочитанных на её версии.
    func leave(conversationId: Int) async throws -> ConversationRemoval {
        try await networkService.request(GroupEndpoint.leave(conversationId: conversationId))
    }
}
