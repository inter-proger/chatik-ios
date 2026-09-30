//
//  NetworkServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сетевого слоя: возвращает заранее заданный результат и запоминает вызовы.
final class NetworkServiceMock: NetworkServiceProtocol {
    var stubbedResult: Result<Any, Error> = .failure(NetworkError.missingResponse)
    /// Значения прогресса, которые `upload` сообщает перед возвратом результата.
    var stubbedUploadProgress: [Double] = []
    private(set) var requestedEndpoints: [Endpoint] = []
    private(set) var uploadedFiles: [MultipartFile] = []
    private(set) var clearSessionCookiesCallCount = 0
    /// Вызывается внутри `request` до возврата результата — пока вызывающий гарантированно в состоянии загрузки.
    /// `@MainActor`, чтобы из хука можно было читать состояние ViewModel и вызывать её методы.
    var onRequest: (@MainActor () async -> Void)?

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        requestedEndpoints.append(endpoint)
        await onRequest?()
        let value = try stubbedResult.get()
        guard let typed = value as? T else {
            throw NetworkError.decoding("NetworkServiceMock: stubbed \(type(of: value)), expected \(T.self)")
        }
        return typed
    }

    func upload<T: Decodable>(_ endpoint: Endpoint, file: MultipartFile, onProgress: @escaping @Sendable (Double) -> Void) async throws -> T {
        uploadedFiles.append(file)
        stubbedUploadProgress.forEach(onProgress)
        return try await request(endpoint)
    }

    func clearSessionCookies() {
        clearSessionCookiesCallCount += 1
    }
}
