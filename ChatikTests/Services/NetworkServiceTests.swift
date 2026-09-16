//
//  NetworkServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class NetworkServiceTests: XCTestCase {
    private let baseURL = URL(string: "http://localhost:8080")!
    private var cookieStorage: HTTPCookieStorage!
    private var sut: NetworkService!
    private var temporaryFiles: [URL] = []
    /// Своя директория для тел загрузок: проверки «мусор не остался» не зависят от других процессов и тестов.
    private var bodyDirectory: URL!

    override func setUp() {
        super.setUp()
        cookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "ChatikTests.\(UUID().uuidString)")
        bodyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("bodies-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        sut = makeSUT()
    }

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        sut = nil
        cookieStorage = nil
        try? FileManager.default.removeItem(at: bodyDirectory)
        bodyDirectory = nil
        TemporaryFile.remove(temporaryFiles)
        temporaryFiles = []
        super.tearDown()
    }

    // MARK: - Request building

    /// Кейс: POST-запрос с параметрами, содержащими пробел и `&`.
    /// Ожидание: путь собран от baseURL, Content-Type — form-urlencoded, тело закодировано и экранировано.
    func test_post_sendsFormURLEncodedBodyToCorrectPath() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{"userId":1,"login":"ivan","name":"Ivan","avatar":null}}"#)

        let _: User = try await sut.request(AuthEndpoint.login(login: "ivan_1", password: "Pass word&1"))

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/auth/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(captured.bodyString, "login=ivan_1&password=Pass+word%261")
    }

    /// Кейс: GET-запрос с параметрами и кастомным заголовком.
    /// Ожидание: параметры в query string с экранированием, заголовок применён, тело отсутствует.
    func test_get_putsParametersIntoQueryAndAppliesHeaders() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{}}"#)
        let endpoint = TestEndpoint(path: "/items", method: .get, parameters: ["page": "2", "q": "a b"], headers: ["X-Test": "1"])

        let _: EmptyResponse = try await sut.request(endpoint)

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/items?page=2&q=a%20b")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
        XCTAssertNil(captured.bodyString)
    }

    /// Кейс: multipart-загрузка файла с текстовым параметром эндпоинта.
    /// Ожидание: POST на path эндпоинта, `Content-Type: multipart/form-data` с boundary, тело собрано
    /// энкодером с этим же boundary (параметр — текстовое поле, файл — файловая часть с содержимым файла
    /// с диска), ответ разобран; временный файл тела после отправки удалён.
    func test_upload_sendsMultipartBodyFromFileAndDecodesResponse() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{"userId":1,"login":"ivan","name":"Ivan","avatar":null}}"#)
        let endpoint = TestEndpoint(path: "/files/uploadImage", method: .post, parameters: ["filename": "a.jpg"], headers: ["X-Test": "1"])
        let file = try makeMultipartFile(Data("JPEG".utf8))

        let user: User = try await sut.upload(endpoint, file: file, onProgress: { _ in })

        XCTAssertEqual(user, User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/files/uploadImage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(contentType.split(separator: "=").last.map(String.init))
        XCTAssertEqual(contentType, "multipart/form-data; boundary=\(boundary)")
        let expectedBody = try expectedMultipartBody(parameters: ["filename": "a.jpg"], file: file, boundary: boundary)
        XCTAssertEqual(captured.bodyString, String(data: expectedBody, encoding: .utf8))
        XCTAssertTrue(try multipartBodyFiles().isEmpty)
    }

    /// Кейс: `upload` вызван с GET-эндпоинтом.
    /// Ожидание: выброшена `NetworkError.unsupportedMethod(.get)`, запрос на сервер не уходит.
    func test_upload_nonPostEndpoint_throwsUnsupportedMethodWithoutRequest() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{}}"#)
        let endpoint = TestEndpoint(path: "/files/get", method: .get, parameters: [:], headers: nil)
        let file = try makeMultipartFile(Data())

        await assertThrows(NetworkError.unsupportedMethod(.get)) {
            let _: EmptyResponse = try await sut.upload(endpoint, file: file, onProgress: { _ in })
        }

        XCTAssertNil(captured.request)
    }

    /// Кейс: загружаемого файла нет на диске.
    /// Ожидание: выброшена `NetworkError.fileAccess`, запрос на сервер не уходит, временный файл тела не остаётся.
    func test_upload_missingFile_throwsFileAccessWithoutRequest() async throws {
        let captured = stub(status: 200, json: #"{"status":1,"response":{}}"#)
        let endpoint = TestEndpoint(path: "/files/uploadImage", method: .post, parameters: [:], headers: nil)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).jpg")
        let file = MultipartFile(fieldName: "file", filename: "a.jpg", mimeType: "image/jpeg", fileURL: missing)

        do {
            let _: EmptyResponse = try await sut.upload(endpoint, file: file, onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            guard case NetworkError.fileAccess = error else { return XCTFail("Unexpected error: \(error)") }
        }

        XCTAssertNil(captured.request)
        XCTAssertTrue(try multipartBodyFiles().isEmpty)
    }

    /// Кейс: multipart-загрузка вернула `status: 0` с кодом 3002.
    /// Ожидание: выброшена `NetworkError.api(3002)` — обработка ответа общая с `request(_:)`.
    func test_upload_errorStatus_throwsApiError() async throws {
        _ = stub(status: 200, json: #"{"status":0,"errorCode":3002}"#)
        let endpoint = TestEndpoint(path: "/files/uploadImage", method: .post, parameters: [:], headers: nil)
        let file = try makeMultipartFile(Data())

        await assertThrows(NetworkError.api(code: 3002)) {
            let _: EmptyResponse = try await sut.upload(endpoint, file: file, onProgress: { _ in })
        }
    }

    // MARK: - Response handling

    /// Кейс: ответ со `status: 1` и заполненным `response`.
    /// Ожидание: `response` декодирован в запрошенный тип.
    func test_successResponse_returnsDecodedPayload() async throws {
        _ = stub(status: 200, json: #"{"status":1,"response":{"userId":42,"login":"ivan","name":"Ivan Petrov","avatar":null}}"#)

        let user: User = try await sut.request(AuthEndpoint.logout)

        XCTAssertEqual(user, User(userId: 42, login: "ivan", name: "Ivan Petrov", avatar: nil))
    }

    /// Кейс: ответ со `status: 0` и `errorCode`.
    /// Ожидание: выброшена `NetworkError.api` с этим кодом.
    func test_errorStatus_throwsApiErrorWithCode() async {
        _ = stub(status: 200, json: #"{"status":0,"errorCode":2002}"#)

        await assertThrows(NetworkError.api(code: 2002)) {
            let _: User = try await sut.request(AuthEndpoint.logout)
        }
    }

    /// Кейс: ответ со `status: 1`, но без поля `response`.
    /// Ожидание: выброшена `NetworkError.missingResponse`.
    func test_successStatusWithoutResponse_throwsMissingResponse() async {
        _ = stub(status: 200, json: #"{"status":1}"#)

        await assertThrows(NetworkError.missingResponse) {
            let _: User = try await sut.request(AuthEndpoint.logout)
        }
    }

    /// Кейс: HTTP-статус вне диапазона 2xx (500).
    /// Ожидание: выброшена `NetworkError.invalidResponse` с этим статусом, тело не разбирается.
    func test_non2xxHttpStatus_throwsInvalidResponse() async {
        _ = stub(status: 500, json: "")

        await assertThrows(NetworkError.invalidResponse(statusCode: 500)) {
            let _: User = try await sut.request(AuthEndpoint.logout)
        }
    }

    /// Кейс: тело ответа — не JSON.
    /// Ожидание: выброшена `NetworkError.decoding`.
    func test_malformedJson_throwsDecodingError() async {
        _ = stub(status: 200, json: "not json")

        do {
            let _: User = try await sut.request(AuthEndpoint.logout)
            XCTFail("Expected decoding error")
        } catch NetworkError.decoding {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Кейс: URLSession завершился ошибкой (нет сети).
    /// Ожидание: выброшена `NetworkError.transport` с исходной `URLError`, код ошибки сохранён.
    func test_transportFailure_throwsTransportError() async {
        URLProtocolStub.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        await assertThrows(NetworkError.transport(URLError(.notConnectedToInternet))) {
            let _: User = try await sut.request(AuthEndpoint.logout)
        }
    }

    // MARK: - Глобальная обработка 2003

    /// Кейс: обычный запрос вернул `status: 0, errorCode: 2003` при наличии cookie сессии.
    /// Ожидание: cookie очищены, обработчик `onUnauthorized` вызван и завершён до проброса ошибки `api(2003)`.
    func test_unauthorizedCode_clearsCookiesAndNotifiesHandler() async throws {
        let flag = UnauthorizedFlag()
        sut = makeSUT(onUnauthorized: {
            try? await Task.sleep(for: .milliseconds(50))
            flag.isCalled = true
        })
        cookieStorage.setCookie(try makeSessionCookie())
        _ = stub(status: 200, json: #"{"status":0,"errorCode":2003}"#)

        await assertThrows(NetworkError.api(code: 2003)) {
            let _: User = try await sut.request(AuthEndpoint.login(login: "ivan", password: "x"))
        }

        XCTAssertTrue(flag.isCalled)
        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count ?? 0, 0)
    }

    /// Кейс: запрос, который сам завершает сессию (`/auth/logout`), вернул 2003.
    /// Ожидание: это штатный ответ — обработчик не вызывается, cookie не трогаются, ошибка `api(2003)` проброшена.
    func test_unauthorizedCode_onSessionTerminatingEndpoint_doesNotNotifyHandler() async throws {
        let flag = UnauthorizedFlag()
        sut = makeSUT(onUnauthorized: { flag.isCalled = true })
        cookieStorage.setCookie(try makeSessionCookie())
        _ = stub(status: 200, json: #"{"status":0,"errorCode":2003}"#)

        await assertThrows(NetworkError.api(code: 2003)) {
            let _: EmptyResponse = try await sut.request(AuthEndpoint.logout)
        }

        XCTAssertFalse(flag.isCalled)
        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count, 1)
    }

    /// Кейс: запрос вернул другую ошибку API (2002) или успех.
    /// Ожидание: обработчик `onUnauthorized` не вызывается, cookie сохраняются.
    func test_otherResponses_doNotNotifyHandler() async throws {
        let flag = UnauthorizedFlag()
        sut = makeSUT(onUnauthorized: { flag.isCalled = true })
        cookieStorage.setCookie(try makeSessionCookie())

        _ = stub(status: 200, json: #"{"status":0,"errorCode":2002}"#)
        await assertThrows(NetworkError.api(code: 2002)) {
            let _: User = try await sut.request(AuthEndpoint.login(login: "ivan", password: "x"))
        }

        _ = stub(status: 200, json: #"{"status":1,"response":{"userId":1,"login":"ivan","name":"Ivan","avatar":null}}"#)
        let _: User = try await sut.request(AuthEndpoint.login(login: "ivan", password: "x"))

        XCTAssertFalse(flag.isCalled)
        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count, 1)
    }

    // MARK: - Cookies

    /// Кейс: в хранилище есть cookie для домена baseURL.
    /// Ожидание: после `clearSessionCookies()` cookie для baseURL удалены.
    func test_clearSessionCookies_removesCookiesForBaseURL() throws {
        cookieStorage.setCookie(try makeSessionCookie())
        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count, 1)

        sut.clearSessionCookies()

        XCTAssertEqual(cookieStorage.cookies(for: baseURL)?.count ?? 0, 0)
    }

    // MARK: - Helpers

    /// Создаёт сервис над стабом `URLSession` с собственной директорией тел и обработчиком 2003.
    private func makeSUT(onUnauthorized: (@Sendable () async -> Void)? = nil) -> NetworkService {
        NetworkService(
            session: URLProtocolStub.makeSession(),
            baseURL: baseURL,
            cookieStorage: cookieStorage,
            bodyDirectory: bodyDirectory,
            onUnauthorized: onUnauthorized
        )
    }

    /// Создаёт cookie сессии `PHPSESSID` для домена baseURL.
    private func makeSessionCookie() throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: "PHPSESSID", .value: "abc", .domain: "localhost", .path: "/"
        ]))
    }

    /// Подставляет ответ сервера и возвращает контейнер с перехваченным запросом. Тело читается сразу
    /// при перехвате: тело загрузки лежит во временном файле, который после отправки удаляется.
    private func stub(status: Int, json: String) -> CapturedRequest {
        let captured = CapturedRequest()
        URLProtocolStub.requestHandler = { request in
            captured.request = request
            captured.bodyString = request.bodyString
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        return captured
    }

    /// Создаёт во временной директории файл с содержимым и описывает его как часть формы `file`.
    private func makeMultipartFile(_ contents: Data) throws -> MultipartFile {
        let url = try TemporaryFile.make(contents, fileExtension: "jpg")
        temporaryFiles.append(url)
        return MultipartFile(fieldName: "file", filename: "a.jpg", mimeType: "image/jpeg", fileURL: url)
    }

    /// Собирает энкодером ожидаемое тело с тем же boundary, что и в перехваченном запросе.
    private func expectedMultipartBody(parameters: [String: String], file: MultipartFile, boundary: String) throws -> Data {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).expected")
        temporaryFiles.append(destination)
        try MultipartFormEncoder.write(parameters: parameters, file: file, boundary: boundary, to: destination)
        return try Data(contentsOf: destination)
    }

    /// Содержимое директории тел загрузок — чтобы проверить, что после отправки временных файлов не остаётся.
    private func multipartBodyFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: bodyDirectory.path))
    }

    /// Проверяет, что замыкание бросает ровно ожидаемую `NetworkError`.
    private func assertThrows(
        _ expected: NetworkError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as NetworkError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class CapturedRequest: @unchecked Sendable {
    var request: URLRequest?
    /// Тело запроса на момент перехвата.
    var bodyString: String?
}

/// Флаг вызова обработчика `onUnauthorized` из `@Sendable`-замыкания.
private final class UnauthorizedFlag: @unchecked Sendable {
    var isCalled = false
}

private struct TestEndpoint: Endpoint {
    let path: String
    let method: HTTPMethod
    let parameters: [String: String]
    let headers: [String: String]?
}
