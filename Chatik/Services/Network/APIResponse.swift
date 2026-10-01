//
//  APIResponse.swift
//  Chatik
//

import Foundation

/// Общая обёртка ответа сервера.
/// `status == 1` — успех, `response` содержит данные метода, `actions` — указания клиенту (поле может отсутствовать).
/// `status == 0` — ошибка, `errorCode` содержит код ошибки.
struct APIResponse<T: Decodable>: Decodable {
    let status: Int
    let response: T?
    let errorCode: Int?
    /// Указания клиенту, которые он умеет выполнять; неизвестные и битые пропущены. Пустой, если поля нет.
    let actions: [APIAction]

    var isSuccess: Bool { status == 1 }

    private enum CodingKeys: String, CodingKey {
        case status, response, errorCode, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Int.self, forKey: .status)
        response = try container.decodeIfPresent(T.self, forKey: .response)
        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        // Битый массив `actions` не должен ронять ответ: данные метода важнее указаний.
        let lossyActions = (try? container.decodeIfPresent([LossyAPIAction].self, forKey: .actions)) ?? nil
        actions = lossyActions?.compactMap(\.action) ?? []
    }
}

/// Пустой ответ для методов, возвращающих `"response": {}`.
struct EmptyResponse: Decodable, Equatable {}
