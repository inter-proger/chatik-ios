//
//  APIResponse.swift
//  Chatik
//

import Foundation

/// Общая обёртка ответа сервера.
/// `status == 1` — успех, `response` содержит данные метода.
/// `status == 0` — ошибка, `errorCode` содержит код ошибки.
struct APIResponse<T: Decodable>: Decodable {
    let status: Int
    let response: T?
    let errorCode: Int?

    var isSuccess: Bool { status == 1 }
}

/// Пустой ответ для методов, возвращающих `"response": {}`.
struct EmptyResponse: Decodable, Equatable {}
