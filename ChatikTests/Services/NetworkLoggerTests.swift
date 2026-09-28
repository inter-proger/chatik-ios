//
//  NetworkLoggerTests.swift
//  ChatikTests
//

#if DEBUG
import XCTest
@testable import Chatik

final class NetworkLoggerTests: XCTestCase {
    private let url = URL(string: "http://localhost:8080/auth/login")!

    /// Кейс: POST-запрос формы с паролем.
    /// Ожидание: в логе метод, URL, заголовки и тело, значение пароля замаскировано.
    func test_requestDescription_post_masksPassword() {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("login=ivan&password=secret".utf8)

        let description = NetworkLogger.requestDescription(request)

        XCTAssertEqual(description, """
        ➡️ POST http://localhost:8080/auth/login
        Content-Type: application/x-www-form-urlencoded
        login=ivan&password=***
        """)
    }

    /// Кейс: GET-запрос без тела и заголовков.
    /// Ожидание: в логе одна строка — метод и URL с query.
    func test_requestDescription_get_withoutBody() {
        let request = URLRequest(url: URL(string: "http://localhost:8080/users/getList?count=30")!)

        XCTAssertEqual(NetworkLogger.requestDescription(request), "➡️ GET http://localhost:8080/users/getList?count=30")
    }

    /// Кейс: upload-запрос с телом из файла.
    /// Ожидание: вместо содержимого в логе размер файла.
    func test_requestDescription_upload_showsFileSize() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).multipart")
        try Data(count: 42).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let description = NetworkLogger.requestDescription(request, bodyFileURL: file)

        XCTAssertTrue(description.hasSuffix("<тело из файла, 42 байт>"), description)
    }

    /// Кейс: заголовки запроса, среди которых есть секретные (в любом регистре).
    /// Ожидание: значения секретных заголовков скрыты, остальные выводятся как есть, порядок — по имени.
    func test_headerLines_masksSensitiveHeaders() {
        let headers = [
            "Content-Type": "application/x-www-form-urlencoded",
            "Cookie": "PHPSESSID=abc",
            "authorization": "Bearer token",
            "X-Test": "1",
        ]

        XCTAssertEqual(NetworkLogger.headerLines(headers), [
            "Content-Type: application/x-www-form-urlencoded",
            "Cookie: ***",
            "X-Test: 1",
            "authorization: ***",
        ])
    }

    /// Кейс: тела формы с чувствительными и обычными полями.
    /// Ожидание: маскируются только значения чувствительных полей, порядок и прочие пары сохраняются.
    func test_maskFormFields() {
        let cases = [
            ("login=ivan&password=secret", "login=ivan&password=***"),
            ("password=a%26b&name=Ivan", "password=***&name=Ivan"),
            ("password=", "password=***"),
            ("login=ivan", "login=ivan"),
            ("passwordHint=x", "passwordHint=x"),
        ]

        for (form, expected) in cases {
            XCTAssertEqual(NetworkLogger.maskFormFields(form), expected, form)
        }
    }

    /// Кейс: ответ сервера с JSON-телом.
    /// Ожидание: в логе статус, метод, URL, время и JSON с отступами, без экранирования `/`.
    func test_responseDescription_json_isPrettyPrinted() {
        let request = URLRequest(url: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = Data(#"{"status":1,"url":"http://a/b"}"#.utf8)

        let description = NetworkLogger.responseDescription(response, data: data, for: request, duration: .milliseconds(123))

        XCTAssertEqual(description, """
        ⬅️ 200 GET http://localhost:8080/auth/login (123 ms)
        {
          "status" : 1,
          "url" : "http://a/b"
        }
        """)
    }

    /// Кейс: тело ответа — не JSON или бинарные данные.
    /// Ожидание: текст выводится как есть, бинарные данные — размером.
    func test_bodyDescription_nonJSON() {
        XCTAssertEqual(NetworkLogger.bodyDescription(Data("Not Found".utf8)), "Not Found")
        XCTAssertEqual(NetworkLogger.bodyDescription(Data([0xFF, 0xFE, 0x00])), "<3 байт>")
    }

    /// Кейс: тело ответа длиннее допустимого.
    /// Ожидание: тело обрезано до `maxBodyLength` символов с пометкой о полном размере.
    func test_bodyDescription_long_isTruncated() {
        let text = String(repeating: "a", count: NetworkLogger.maxBodyLength + 1)

        let description = NetworkLogger.bodyDescription(Data(text.utf8))

        XCTAssertTrue(description.hasPrefix(String(repeating: "a", count: NetworkLogger.maxBodyLength) + "…"))
        XCTAssertTrue(description.hasSuffix("<обрезано, всего \(text.count) байт>"))
    }

    /// Кейс: запрос завершился ошибкой без ответа сервера.
    /// Ожидание: в логе метод, URL, время и ошибка.
    func test_failureDescription() {
        let error = NetworkError.transport(URLError(.notConnectedToInternet))

        let description = NetworkLogger.failureDescription(error, for: URLRequest(url: url), duration: .milliseconds(5))

        XCTAssertTrue(description.hasPrefix("❌ GET http://localhost:8080/auth/login (5 ms)\n"), description)
    }
}
#endif
