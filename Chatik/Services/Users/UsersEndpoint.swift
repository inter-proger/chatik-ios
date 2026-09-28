//
//  UsersEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/users/*`. Требуют активной сессии (cookie `PHPSESSID`).
enum UsersEndpoint: Endpoint {
    /// GET /users/getList — список пользователей с фильтром и постраничной выдачей. Ответ: `UsersPage`.
    /// Необязательные параметры не отправляются, если не заданы, — сервер применит значения по умолчанию.
    case getList(query: String?, maxId: Int?, count: Int?)

    var path: String {
        switch self {
        case .getList: return "/users/getList"
        }
    }

    var method: HTTPMethod { .get }

    var parameters: [String: String] {
        switch self {
        case let .getList(query, maxId, count):
            var parameters: [String: String] = [:]
            parameters["query"] = query
            parameters["maxId"] = maxId.map(String.init)
            parameters["count"] = count.map(String.init)
            return parameters
        }
    }

    var headers: [String: String]? { nil }
}
