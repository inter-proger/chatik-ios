//
//  NetworkService.swift
//  Chatik
//

import Foundation

protocol NetworkServiceProtocol {
    /// Выполняет запрос и возвращает содержимое поля `response` успешного ответа.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    /// Загружает файл POST-запросом с телом `multipart/form-data`: параметры эндпоинта уходят текстовыми полями,
    /// `file` — файловой частью. Возвращает содержимое поля `response` успешного ответа.
    func upload<T: Decodable>(_ endpoint: Endpoint, file: MultipartFile) async throws -> T
    /// Очищает cookie сессии (`PHPSESSID`) для базового URL.
    func clearSessionCookies()
}

final class NetworkService: NetworkServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let cookieStorage: HTTPCookieStorage
    private let onUnauthorized: (@Sendable () async -> Void)?
    private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - session: сессия для выполнения запросов. По умолчанию `.shared` — она сама
    ///     сохраняет и подставляет cookie `PHPSESSID` через `HTTPCookieStorage.shared`.
    ///   - baseURL: базовый адрес API.
    ///   - cookieStorage: хранилище cookie, которое использует `session`.
    ///   - onUnauthorized: вызывается, когда запрос (кроме `Endpoint.terminatesSession`) вернул код 2003 —
    ///     сессия недействительна. Cookie сессии к этому моменту уже очищены; ошибка пробрасывается
    ///     вызывающему только после завершения обработчика, чтобы к её обработке сессия уже была закрыта.
    init(
        session: URLSession = .shared,
        baseURL: URL = AppConfig.baseURL,
        cookieStorage: HTTPCookieStorage = .shared,
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
        self.onUnauthorized = onUnauthorized
    }

    /// Выполняет запрос к API, проверяет HTTP-статус и общую обёртку `{status, response, errorCode}`.
    /// - Parameter endpoint: описание запроса (path, метод, параметры, заголовки).
    /// - Returns: декодированное поле `response`.
    /// - Throws: `NetworkError` при транспортной ошибке, неверном HTTP-статусе,
    ///   `status = 0` от сервера или ошибке декодирования.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        try await send(makeURLRequest(for: endpoint), for: endpoint)
    }

    /// Загружает файл через `multipart/form-data`; обработка ответа такая же, как у `request(_:)`.
    /// - Parameters:
    ///   - endpoint: описание запроса; `parameters` уходят текстовыми полями формы.
    ///   - file: файл, который уходит файловой частью формы.
    /// - Returns: декодированное поле `response`.
    /// - Throws: `NetworkError.unsupportedMethod`, если `endpoint.method != .post` — запрос не отправляется.
    func upload<T: Decodable>(_ endpoint: Endpoint, file: MultipartFile) async throws -> T {
        guard endpoint.method == .post else { throw NetworkError.unsupportedMethod(endpoint.method) }
        return try await send(makeMultipartRequest(for: endpoint, file: file), for: endpoint)
    }

    /// Удаляет все cookie, относящиеся к базовому URL API.
    func clearSessionCookies() {
        cookieStorage.cookies(for: baseURL)?.forEach { cookieStorage.deleteCookie($0) }
    }

    // MARK: - Private

    /// Выполняет собранный запрос, проверяет HTTP-статус и общую обёртку `{status, response, errorCode}`.
    private func send<T: Decodable>(_ request: URLRequest, for endpoint: Endpoint) async throws -> T {
        let (data, response) = try await perform(request)
        try validate(response)
        let apiResponse: APIResponse<T> = try decode(data)
        await handleUnauthorizedIfNeeded(apiResponse, for: endpoint)
        return try unwrap(apiResponse)
    }

    /// Выполняет запрос, оборачивая `URLError` в `NetworkError.transport`; прочие ошибки пробрасываются как есть.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw NetworkError.transport(error)
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

    /// Собирает POST-запрос с телом `multipart/form-data`: параметры эндпоинта — текстовые поля, `file` — файл.
    private func makeMultipartRequest(for endpoint: Endpoint, file: MultipartFile) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(MultipartFormEncoder.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormEncoder.encode(parameters: endpoint.parameters, file: file, boundary: boundary)
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

    /// Глобальная обработка кода 2003: сессия на сервере недействительна —
    /// очищает cookie и уведомляет обработчик, чтобы приложение завершило сессию локально.
    /// Для запросов, которые сами завершают сессию (`terminatesSession`), 2003 — штатный ответ, обработчик не вызывается.
    private func handleUnauthorizedIfNeeded<T: Decodable>(_ apiResponse: APIResponse<T>, for endpoint: Endpoint) async {
        guard !endpoint.terminatesSession else { return }
        guard !apiResponse.isSuccess, apiResponse.errorCode == NetworkError.Code.unauthorized else { return }
        clearSessionCookies()
        await onUnauthorized?()
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
