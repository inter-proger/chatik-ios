//
//  MultipartFormEncoderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MultipartFormEncoderTests: XCTestCase {
    private let boundary = "TestBoundary"

    /// Кейс: два текстовых поля в произвольном порядке и файл.
    /// Ожидание: поля отсортированы по ключу и идут перед файлом, у файла — `filename` и `Content-Type`,
    /// тело завершается закрывающим разделителем; разделители строк — CRLF.
    func test_encode_buildsSortedFieldsThenFileThenClosingBoundary() {
        let file = MultipartFile(fieldName: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: Data("JPEG".utf8))

        let body = MultipartFormEncoder.encode(parameters: ["b": "2", "a": "1"], file: file, boundary: boundary)

        let expected = [
            "--TestBoundary",
            "Content-Disposition: form-data; name=\"a\"",
            "",
            "1",
            "--TestBoundary",
            "Content-Disposition: form-data; name=\"b\"",
            "",
            "2",
            "--TestBoundary",
            "Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"",
            "Content-Type: image/jpeg",
            "",
            "JPEG",
            "--TestBoundary--",
            "",
        ].joined(separator: "\r\n")
        XCTAssertEqual(String(data: body, encoding: .utf8), expected)
    }

    /// Кейс: параметров нет, только файл.
    /// Ожидание: тело состоит из одной файловой части и закрывающего разделителя.
    func test_encode_withoutParameters_containsOnlyFilePart() {
        let file = MultipartFile(fieldName: "file", filename: "a.png", mimeType: "image/png", data: Data([0x89, 0x50]))

        let body = MultipartFormEncoder.encode(parameters: [:], file: file, boundary: boundary)

        var expected = Data("--TestBoundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        expected.append(Data([0x89, 0x50]))
        expected.append(Data("\r\n--TestBoundary--\r\n".utf8))
        XCTAssertEqual(body, expected)
    }

    /// Кейс: имя файла содержит кавычку и перевод строки.
    /// Ожидание: опасные символы заменены на `%22` / `%0A`, заголовок остаётся одной строкой.
    func test_encode_escapesQuotesAndLineBreaksInFilename() throws {
        let file = MultipartFile(fieldName: "file", filename: "my\"file\n.jpg", mimeType: "image/jpeg", data: Data())

        let body = MultipartFormEncoder.encode(parameters: [:], file: file, boundary: boundary)

        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("filename=\"my%22file%0A.jpg\""), text)
    }

    /// Кейс: заголовок `Content-Type` для заданного разделителя.
    /// Ожидание: `multipart/form-data; boundary=<boundary>`.
    func test_contentType_includesBoundary() {
        XCTAssertEqual(MultipartFormEncoder.contentType(boundary: boundary), "multipart/form-data; boundary=TestBoundary")
    }
}
