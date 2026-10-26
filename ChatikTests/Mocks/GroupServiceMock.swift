//
//  GroupServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок запросов `/groups/*`: ответы задаёт тест, запросы запоминаются.
final class GroupServiceMock: GroupServiceProtocol {
    var stubbedCreate: Result<CreatedGroup, Error> = .failure(NetworkError.missingResponse)
    var stubbedAddMembers: [Result<AddMembersResult, Error>] = []
    var stubbedChangeOwner: Result<GroupInfo, Error> = .failure(NetworkError.missingResponse)
    var stubbedRemoveMembers: Result<RemoveMembersResult, Error> = .failure(NetworkError.missingResponse)
    private(set) var removeMembersRequests: [(conversationId: Int, userIds: [Int])] = []
    /// Ответы `fetchInfo` по порядку; кончились — `missingResponse`.
    var stubbedInfos: [Result<GroupInfo, Error>] = []
    var stubbedLeave: Result<ConversationRemoval, Error> = .failure(NetworkError.missingResponse)
    /// Задерживает ответы `fetchInfo` до `open()`.
    var fetchInfoGate: Gate?
    /// Задерживает ответы на действия (`create`, `addMembers`, `changeOwner`, `leave`) до `open()`.
    var actionGate: Gate?
    private(set) var createRequests: [(name: String, description: String?, avatarFileId: Int?)] = []
    private(set) var addMembersRequests: [(conversationId: Int, userIds: [Int])] = []
    private(set) var changeOwnerRequests: [(conversationId: Int, newOwnerUserId: Int)] = []
    private(set) var fetchInfoRequests: [Int] = []
    private(set) var leaveRequests: [Int] = []

    func create(name: String, description: String?, avatarFileId: Int?) async throws -> CreatedGroup {
        createRequests.append((name, description, avatarFileId))
        await actionGate?.wait()
        return try stubbedCreate.get()
    }

    func addMembers(conversationId: Int, userIds: [Int]) async throws -> AddMembersResult {
        addMembersRequests.append((conversationId, userIds))
        await actionGate?.wait()
        let result = stubbedAddMembers.isEmpty ? .failure(NetworkError.missingResponse) : stubbedAddMembers.removeFirst()
        return try result.get()
    }

    func removeMembers(conversationId: Int, userIds: [Int]) async throws -> RemoveMembersResult {
        removeMembersRequests.append((conversationId, userIds))
        await actionGate?.wait()
        return try stubbedRemoveMembers.get()
    }

    func changeOwner(conversationId: Int, newOwnerUserId: Int) async throws -> GroupInfo {
        changeOwnerRequests.append((conversationId, newOwnerUserId))
        await actionGate?.wait()
        return try stubbedChangeOwner.get()
    }

    func fetchInfo(conversationId: Int) async throws -> GroupInfo {
        fetchInfoRequests.append(conversationId)
        await fetchInfoGate?.wait()
        let result = stubbedInfos.isEmpty ? .failure(NetworkError.missingResponse) : stubbedInfos.removeFirst()
        return try result.get()
    }

    func leave(conversationId: Int) async throws -> ConversationRemoval {
        leaveRequests.append(conversationId)
        await actionGate?.wait()
        return try stubbedLeave.get()
    }
}
