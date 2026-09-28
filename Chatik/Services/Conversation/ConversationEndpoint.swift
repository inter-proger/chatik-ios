//
//  ConversationEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/conversations/*`. Требуют активной сессии (cookie `PHPSESSID`).
enum ConversationEndpoint: Endpoint {
    /// POST /conversations/createSingle — личная переписка с указанным пользователем.
    /// Ответ: `ConversationResponse` с созданной или уже существующей перепиской.
    case createSingle(userId: Int)
    /// GET /conversations/getList — переписки текущего пользователя, сначала самые новые. Ответ: `ConversationsPage`.
    /// Необязательные параметры не отправляются, если не заданы, — сервер применит значения по умолчанию.
    case getList(offset: Int?, count: Int?)

    var path: String {
        switch self {
        case .createSingle: return "/conversations/createSingle"
        case .getList: return "/conversations/getList"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .createSingle: return .post
        case .getList: return .get
        }
    }

    var parameters: [String: String] {
        switch self {
        case let .createSingle(userId):
            return ["userId": String(userId)]
        case let .getList(offset, count):
            var parameters: [String: String] = [:]
            parameters["offset"] = offset.map(String.init)
            parameters["count"] = count.map(String.init)
            return parameters
        }
    }

    var headers: [String: String]? { nil }
}
