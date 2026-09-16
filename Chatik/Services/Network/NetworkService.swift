//
//  NetworkService.swift
//  Chatik
//

import Foundation

protocol NetworkServiceProtocol {
    /// Выполняет запрос и возвращает содержимое поля `response` успешного ответа.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    /// Загружает файл POST-запросом с телом `multipart/form-data`: параметры эндпоинта уходят текстовыми полями,
    /// `file` — файловой частью. Тело собирается во временном файле и отправляется из него — содержимое файла
    /// в память целиком не читается. Возвращает содержимое поля `response` успешного ответа.
    /// `onProgress` получает долю отправленного тела от 0 до 1; вызывается не на main.
    func upload<T: Decodable>(_ endpoint: Endpoint, file: MultipartFile, onProgress: @escaping @Sendable (Double) -> Void) async throws -> T
    /// Очищает cookie сессии (`PHPSESSID`) для базового URL.
    func clearSessionCookies()
}

final class NetworkService: NetworkServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let cookieStorage: HTTPCookieStorage
    /// Куда складываются временные файлы с телами загрузок; каждый удаляется сразу после отправки.
    private let bodyDirectory: URL
    private let onUnauthorized: (@Sendable () async -> Void)?
    private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - session: сессия для выполнения запросов. По умолчанию `.shared` — она сама
    ///     сохраняет и подставляет cookie `PHPSESSID` через `HTTPCookieStorage.shared`.
    ///   - baseURL: базовый адрес API.
    ///   - cookieStorage: хранилище cookie, которое использует `session`.
    ///   - bodyDirectory: директория для временных файлов с телами загрузок.
    ///   - onUnauthorized: вызывается, когда запрос (кроме `Endpoint.terminatesSession`) вернул код 2003 —
    ///     сессия недействительна. Cookie сессии к этому моменту уже очищены; ошибка пробрасывается
    ///     вызывающему только после завершения обработчика, чтобы к её обработке сессия уже была закрыта.
    init(
        session: URLSession = .shared,
        baseURL: URL = AppConfig.baseURL,
        cookieStorage: HTTPCookieStorage = .shared,
        bodyDirectory: URL = FileManager.default.temporaryDirectory,
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
        self.bodyDirectory = bodyDirectory
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

    /// Загружает файл через `multipart/form-data` из временного файла с телом; обработка ответа такая же,
    /// как у `request(_:)`. Временный файл удаляется после отправки независимо от результата.
    /// - Parameters:
    ///   - endpoint: описание запроса; `parameters` уходят текстовыми полями формы.
    ///   - file: файл, который уходит файловой частью формы.
    ///   - onProgress: получает долю отправленного тела от 0 до 1 по мере отправки; вызывается не на main.
    /// - Returns: декодированное поле `response`.
    /// - Throws: `NetworkError.unsupportedMethod`, если `endpoint.method != .post`, и `NetworkError.fileAccess`,
    ///   если тело не удалось собрать на диске — в обоих случаях запрос не отправляется.
    func upload<T: Decodable>(
        _ endpoint: Endpoint,
        file: MultipartFile,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> T {
        guard endpoint.method == .post else { throw NetworkError.unsupportedMethod(endpoint.method) }
        let (request, bodyURL) = try makeMultipartRequest(for: endpoint, file: file)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let (data, response) = try await performUpload(request, bodyURL: bodyURL, onProgress: onProgress)
        return try await decodeAPIResponse(data: data, response: response, for: endpoint)
    }

    /// Удаляет все cookie, относящиеся к базовому URL API.
    func clearSessionCookies() {
        cookieStorage.cookies(for: baseURL)?.forEach { cookieStorage.deleteCookie($0) }
    }

    // MARK: - Private

    /// Выполняет собранный запрос и разбирает ответ.
    private func send<T: Decodable>(_ request: URLRequest, for endpoint: Endpoint) async throws -> T {
        let (data, response) = try await perform(request)
        return try await decodeAPIResponse(data: data, response: response, for: endpoint)
    }

    /// Проверяет HTTP-статус и общую обёртку `{status, response, errorCode}` полученного ответа.
    private func decodeAPIResponse<T: Decodable>(data: Data, response: URLResponse, for endpoint: Endpoint) async throws -> T {
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

    /// Отправляет тело из файла `bodyURL` upload-задачей, чтобы `URLSession` читала его с диска потоком
    /// и сообщала о прогрессе отправки через делегат задачи.
    /// `URLError` оборачивается в `NetworkError.transport`; прочие ошибки пробрасываются как есть.
    /// Доставка прогресса юнит-тестами не покрывается: `URLProtocol`-стаб не генерирует `didSendBodyData`;
    /// проверяется интеграционно против локального сервера (`NetworkServiceUploadIntegrationTests`).
    private func performUpload(
        _ request: URLRequest,
        bodyURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.upload(for: request, fromFile: bodyURL, delegate: UploadProgressDelegate(onProgress: onProgress))
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

    /// Собирает POST-запрос `multipart/form-data`: параметры эндпоинта — текстовые поля, `file` — файл.
    /// Тело записывается во временный файл и возвращается его адресом — upload-задача читает тело с диска.
    /// Удаление временного файла — на вызывающей стороне.
    private func makeMultipartRequest(for endpoint: Endpoint, file: MultipartFile) throws -> (URLRequest, URL) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(MultipartFormEncoder.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        applyHeaders(endpoint.headers, to: &request)
        let bodyURL = try writeMultipartBody(parameters: endpoint.parameters, file: file, boundary: boundary)
        return (request, bodyURL)
    }

    /// Записывает тело `multipart/form-data` во временный файл. При ошибке недописанный файл удаляется,
    /// а ошибка файловой системы оборачивается в `NetworkError.fileAccess`.
    private func writeMultipartBody(parameters: [String: String], file: MultipartFile, boundary: String) throws -> URL {
        let bodyURL = bodyDirectory.appendingPathComponent("\(UUID().uuidString).multipart")
        do {
            try MultipartFormEncoder.write(parameters: parameters, file: file, boundary: boundary, to: bodyURL)
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw NetworkError.fileAccess(String(describing: error))
        }
        return bodyURL
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
