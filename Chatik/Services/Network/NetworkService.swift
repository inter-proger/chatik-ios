//
//  NetworkService.swift
//  Chatik
//

import Foundation

protocol NetworkServiceProtocol {
    /// Выполняет запрос и возвращает содержимое поля `response` успешного ответа.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    /// Очищает cookie сессии (`PHPSESSID`) для базового URL.
    func clearSessionCookies()
}

final class NetworkService: NetworkServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let cookieStorage: HTTPCookieStorage
    private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - session: сессия для выполнения запросов. По умолчанию `.shared` — она сама
    ///     сохраняет и подставляет cookie `PHPSESSID` через `HTTPCookieStorage.shared`.
    ///   - baseURL: базовый адрес API.
    ///   - cookieStorage: хранилище cookie, которое использует `session`.
    init(
        session: URLSession = .shared,
        baseURL: URL = AppConfig.baseURL,
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
    }

    /// Выполняет запрос к API, проверяет HTTP-статус и общую обёртку `{status, response, errorCode}`.
    /// - Parameter endpoint: описание запроса (path, метод, параметры, заголовки).
    /// - Returns: декодированное поле `response`.
    /// - Throws: `NetworkError` при транспортной ошибке, неверном HTTP-статусе,
    ///   `status = 0` от сервера или ошибке декодирования.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try makeURLRequest(for: endpoint)
        let (data, response) = try await perform(request)
        try validate(response)
        let apiResponse: APIResponse<T> = try decode(data)
        return try unwrap(apiResponse)
    }

    /// Удаляет все cookie, относящиеся к базовому URL API.
    func clearSessionCookies() {
        cookieStorage.cookies(for: baseURL)?.forEach { cookieStorage.deleteCookie($0) }
    }

    // MARK: - Private

    /// Выполняет запрос, оборачивая транспортные ошибки в `NetworkError.transport`.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    /// Собирает `URLRequest` в зависимости от HTTP-метода эндпоинта.
    private func makeURLRequest(for endpoint: Endpoint) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint.path)
        switch endpoint.method {
        case .get:
            return try makeGETRequest(url: url, endpoint: endpoint)
        case .post:
            return makePOSTRequest(url: url, endpoint: endpoint)
        }
    }

    /// Собирает GET-запрос с параметрами в query string.
    private func makeGETRequest(url: URL, endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !endpoint.parameters.isEmpty {
            components?.queryItems = endpoint.parameters
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components?.url else { throw NetworkError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = HTTPMethod.get.rawValue
        applyHeaders(endpoint.headers, to: &request)
        return request
    }

    /// Собирает POST-запрос с параметрами в теле как `x-www-form-urlencoded`.
    private func makePOSTRequest(url: URL, endpoint: Endpoint) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoder.encode(endpoint.parameters).data(using: .utf8)
        applyHeaders(endpoint.headers, to: &request)
        return request
    }

    /// Проставляет кастомные заголовки эндпоинта в запрос.
    private func applyHeaders(_ headers: [String: String]?, to request: inout URLRequest) {
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    }

    /// Проверяет, что ответ — HTTP с кодом 2xx.
    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    /// Декодирует JSON, оборачивая ошибку в `NetworkError.decoding`.
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(String(describing: error))
        }
    }

    /// Разбирает общую обёртку: при `status = 0` бросает `NetworkError.api`, иначе возвращает `response`.
    private func unwrap<T: Decodable>(_ apiResponse: APIResponse<T>) throws -> T {
        guard apiResponse.isSuccess else {
            throw NetworkError.api(code: apiResponse.errorCode ?? -1)
        }
        guard let payload = apiResponse.response else {
            throw NetworkError.missingResponse
        }
        return payload
    }
}
