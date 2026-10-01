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
    /// GET /users/getBatch — пользователи по списку id (от 1 до 100). Ответ: `UsersBatch`.
    case getBatch(userIds: [Int])

    /// Сколько id сервер принимает в одном запросе `/users/getBatch`.
    static let batchLimit = 100

    var path: String {
        switch self {
        case .getList: return "/users/getList"
        case .getBatch: return "/users/getBatch"
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
        case let .getBatch(userIds):
            // Сервер принимает список и через запятую, и массивом `userIds[]`; запятая короче и не требует
            // повторяющихся ключей, которых нет в `[String: String]`.
            return ["userIds": userIds.map(String.init).joined(separator: ",")]
        }
    }

    var headers: [String: String]? { nil }

    /// `getBatch` вызывает кэш пользователей, выполняя action `users`: action `users` в его ответе снова попал бы
    /// в кэш, и загрузка ждала бы саму себя — запрос не возвращался бы никогда.
    var dispatchesActions: Bool {
        switch self {
        case .getList: return true
        case .getBatch: return false
        }
    }
}
