//
//  MessageEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/messages/*`. Требуют активной сессии (cookie `PHPSESSID`) и членства в переписке.
enum MessageEndpoint: Endpoint {
    /// GET /messages/getList — сообщения переписки целыми блоками от новых к старым. Ответ: `MessagesPage`.
    /// `.block(nil)` — начиная с самого нового блока; `.receivedAfter` — дельта для синхронизации кэша.
    case getList(conversationId: Int, filter: MessageListFilter)
    /// GET /messages/getBlockBatch — до 10 блоков целиком. Ответ: `MessageBlocksBatch`.
    case getBlockBatch(blockIds: [Int])
    /// POST /messages/send — отправка текстового сообщения от лица текущего пользователя. Ответ: `MessageResponse`.
    /// Идемпотентен по `clientId`: повтор с тем же `clientId` возвращает уже созданное сообщение.
    case send(conversationId: Int, text: String, clientId: String)
    /// POST /messages/edit — замена текста своего сообщения. Ответ: `MessageResponse` с `isEdited == true`.
    case edit(messageId: Int, newText: String)

    var path: String {
        switch self {
        case .getList: return "/messages/getList"
        case .getBlockBatch: return "/messages/getBlockBatch"
        case .send: return "/messages/send"
        case .edit: return "/messages/edit"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getList, .getBlockBatch: return .get
        case .send, .edit: return .post
        }
    }

    var parameters: [String: String] {
        switch self {
        case let .getList(conversationId, filter):
            var parameters = ["conversationId": String(conversationId)]
            switch filter {
            case let .block(blockId):
                parameters["blockId"] = blockId.map(String.init)
            case let .receivedAfter(mark):
                // Метка с запасом у начала эпохи отрицательна, а сервер принимает только неотрицательные (иначе 1004).
                parameters["receivedAfter"] = String(max(mark.milliseconds, 0))
            }
            return parameters
        case let .getBlockBatch(blockIds):
            return ["blockIds": blockIds.map(String.init).joined(separator: ",")]
        case let .send(conversationId, text, clientId):
            return ["conversationId": String(conversationId), "text": text, "clientId": clientId]
        case let .edit(messageId, newText):
            return ["messageId": String(messageId), "newText": newText]
        }
    }

    var headers: [String: String]? { nil }
}
