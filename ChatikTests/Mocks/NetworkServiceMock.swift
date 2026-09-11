//
//  NetworkServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сетевого слоя: возвращает заранее заданный результат и запоминает вызовы.
final class NetworkServiceMock: NetworkServiceProtocol {
    var stubbedResult: Result<Any, Error> = .failure(NetworkError.missingResponse)
    private(set) var requestedEndpoints: [Endpoint] = []
    private(set) var clearSessionCookiesCallCount = 0

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        requestedEndpoints.append(endpoint)
        let value = try stubbedResult.get()
        guard let typed = value as? T else {
            throw NetworkError.decoding("NetworkServiceMock: stubbed \(type(of: value)), expected \(T.self)")
        }
        return typed
    }

    func clearSessionCookies() {
        clearSessionCookiesCallCount += 1
    }
}
