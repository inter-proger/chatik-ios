//
//  MessageEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/messages/*`. Требуют активной сессии (cookie `PHPSESSID`) и членства в переписке.
enum MessageEndpoint: Endpoint {
    /// GET /messages/getList — сообщения переписки целыми блоками от новых к старым, минимум 40.
    /// Ответ: `MessagesPage`. Без `blockId` — начиная с самого нового блока.
    case getList(conversationId: Int, blockId: Int?)
    /// GET /messages/getBlock — сообщения одного блока. Ответ: `MessagesBlock`.
    case getBlock(blockId: Int)
    /// POST /messages/send — отправка текстового сообщения от лица текущего пользователя. Ответ: `MessageResponse`.
    /// Идемпотентен по `clientId`: повтор с тем же `clientId` возвращает уже созданное сообщение.
    case send(conversationId: Int, text: String, clientId: String)
    /// POST /messages/edit — замена текста своего сообщения. Ответ: `MessageResponse` с `isEdited == true`.
    case edit(messageId: Int, newText: String)

    var path: String {
        switch self {
        case .getList: return "/messages/getList"
        case .getBlock: return "/messages/getBlock"
        case .send: return "/messages/send"
        case .edit: return "/messages/edit"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getList, .getBlock: return .get
        case .send, .edit: return .post
        }
    }

    var parameters: [String: String] {
        switch self {
        case let .getList(conversationId, blockId):
            var parameters = ["conversationId": String(conversationId)]
            parameters["blockId"] = blockId.map(String.init)
            return parameters
        case let .getBlock(blockId):
            return ["blockId": String(blockId)]
        case let .send(conversationId, text, clientId):
            return ["conversationId": String(conversationId), "text": text, "clientId": clientId]
        case let .edit(messageId, newText):
            return ["messageId": String(messageId), "newText": newText]
        }
    }

    var headers: [String: String]? { nil }
}
