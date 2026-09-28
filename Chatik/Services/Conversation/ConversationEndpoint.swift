//
//  ConversationEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/conversation/*`. Требуют активной сессии (cookie `PHPSESSID`).
enum ConversationEndpoint: Endpoint {
    /// POST /conversation/createSingle — личная переписка с указанным пользователем.
    /// Ответ: `ConversationResponse` с созданной или уже существующей перепиской.
    case createSingle(userId: Int)

    var path: String {
        switch self {
        case .createSingle: return "/conversation/createSingle"
        }
    }

    var method: HTTPMethod { .post }

    var parameters: [String: String] {
        switch self {
        case let .createSingle(userId):
            return ["userId": String(userId)]
        }
    }

    var headers: [String: String]? { nil }
}
