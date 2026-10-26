//
//  GroupEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/groups/*`. Требуют активной сессии (cookie `PHPSESSID`).
enum GroupEndpoint: Endpoint {
    /// POST /groups/create — группа с текущим пользователем-владельцем. Не идемпотентен. Ответ: `CreatedGroup`.
    case create(name: String, description: String?, avatarFileId: Int?)
    /// POST /groups/addMembers — добавление участников (только владелец), от 1 до 100. Ответ: `AddMembersResult`.
    case addMembers(conversationId: Int, userIds: [Int])
    /// POST /groups/removeMembers — исключение участников (только владелец), от 1 до 100. Ответ: `RemoveMembersResult`.
    case removeMembers(conversationId: Int, userIds: [Int])
    /// POST /groups/changeOwner — передача владения участнику (только владелец). Ответ: `GroupInfoResponse`.
    case changeOwner(conversationId: Int, newOwnerUserId: Int)
    /// GET /groups/getInfo — состав и роли группы. Ответ: `GroupInfoResponse`.
    case getInfo(conversationId: Int)
    /// POST /groups/leave — выход текущего пользователя. Ответ: `ConversationRemoval`.
    case leave(conversationId: Int)

    var path: String {
        switch self {
        case .create: return "/groups/create"
        case .addMembers: return "/groups/addMembers"
        case .removeMembers: return "/groups/removeMembers"
        case .changeOwner: return "/groups/changeOwner"
        case .getInfo: return "/groups/getInfo"
        case .leave: return "/groups/leave"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .create, .addMembers, .removeMembers, .changeOwner, .leave: return .post
        case .getInfo: return .get
        }
    }

    var parameters: [String: String] {
        switch self {
        case let .create(name, description, avatarFileId):
            var parameters = ["name": name]
            parameters["description"] = description
            parameters["avatarFileId"] = avatarFileId.map(String.init)
            return parameters
        case let .addMembers(conversationId, userIds), let .removeMembers(conversationId, userIds):
            return ["conversationId": String(conversationId), "userIds": userIds.map(String.init).joined(separator: ",")]
        case let .changeOwner(conversationId, newOwnerUserId):
            return ["conversationId": String(conversationId), "newOwnerUserId": String(newOwnerUserId)]
        case let .getInfo(conversationId), let .leave(conversationId):
            return ["conversationId": String(conversationId)]
        }
    }

    var headers: [String: String]? { nil }
}
