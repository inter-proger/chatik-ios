//
//  ConversationEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/conversations/*`. Требуют активной сессии (cookie `PHPSESSID`).
enum ConversationEndpoint: Endpoint {
    /// Наибольшее число id в одном запросе `getBatch`.
    static let maxBatchCount = 100

    /// POST /conversations/createSingle — личная переписка с указанным пользователем.
    /// Ответ: `ConversationResponse` с созданной или уже существующей перепиской.
    case createSingle(userId: Int)
    /// GET /conversations/getList — переписки текущего пользователя по убыванию позиции. Ответ: `ConversationsPage`.
    /// Необязательные параметры не отправляются, если не заданы, — сервер применит значения по умолчанию.
    case getList(filter: ConversationListFilter, count: Int?)
    /// GET /conversations/getBatch — переписки по списку id (от 1 до `maxBatchCount`). Ответ: `ConversationsBatch`.
    case getBatch(ids: [Int])

    var path: String {
        switch self {
        case .createSingle: return "/conversations/createSingle"
        case .getList: return "/conversations/getList"
        case .getBatch: return "/conversations/getBatch"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .createSingle: return .post
        case .getList, .getBatch: return .get
        }
    }

    var parameters: [String: String] {
        switch self {
        case let .createSingle(userId):
            return ["userId": String(userId)]
        case let .getList(filter, count):
            var parameters = Self.parameters(for: filter)
            parameters["count"] = count.map(String.init)
            return parameters
        case let .getBatch(ids):
            return ["conversationIds": ids.map(String.init).joined(separator: ",")]
        }
    }

    var headers: [String: String]? { nil }

    /// Параметры фильтра списка. Метка времени не бывает отрицательной: сервер ответил бы ошибкой `1004`,
    /// а запас синхронизации у самого начала эпохи мог бы её такой сделать.
    /// - Parameter filter: фильтр списка.
    private static func parameters(for filter: ConversationListFilter) -> [String: String] {
        var parameters: [String: String] = [:]
        switch filter {
        case let .none(offset):
            parameters["offset"] = offset.map(String.init)
        case let .positionUpdatedAfter(time, offset):
            parameters["positionUpdatedAfter"] = String(max(0, time.milliseconds))
            parameters["offset"] = offset.map(String.init)
        case let .updatedInfoAfter(time, afterId):
            parameters["updatedInfoAfter"] = String(max(0, time.milliseconds))
            parameters["updatedInfoAfterId"] = afterId.map(String.init)
        }
        return parameters
    }
}
