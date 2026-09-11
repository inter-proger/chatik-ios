//
//  Endpoint.swift
//  Chatik
//

import Foundation

/// Описание запроса к API: метод, path, параметры и заголовки.
/// GET-параметры уходят в query string, POST — в теле как `x-www-form-urlencoded`.
protocol Endpoint {
    var path: String { get }
    var method: HTTPMethod { get }
    var parameters: [String: String] { get }
    var headers: [String: String]? { get }
}
