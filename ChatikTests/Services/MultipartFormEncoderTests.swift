//
//  MultipartFormEncoderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MultipartFormEncoderTests: XCTestCase {
    private let boundary = "TestBoundary"
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        TemporaryFile.remove(temporaryFiles)
        temporaryFiles = []
        super.tearDown()
    }

    /// Кейс: два текстовых поля в произвольном порядке и файл.
    /// Ожидание: поля отсортированы по ключу и идут перед файлом, у файла — `filename` и `Content-Type`,
    /// тело завершается закрывающим разделителем; разделители строк — CRLF.
    func test_write_buildsSortedFieldsThenFileThenClosingBoundary() throws {
        let file = try makeMultipartFile(Data("JPEG".utf8), filename: "photo.jpg", mimeType: "image/jpeg")

        let body = try write(parameters: ["b": "2", "a": "1"], file: file)

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

    /// Кейс: параметров нет, только файл с бинарным содержимым.
    /// Ожидание: тело состоит из одной файловой части и закрывающего разделителя, байты файла не изменены.
    func test_write_withoutParameters_containsOnlyFilePart() throws {
        let file = try makeMultipartFile(Data([0x89, 0x50]), filename: "a.png", mimeType: "image/png")

        let body = try write(parameters: [:], file: file)

        var expected = Data("--TestBoundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        expected.append(Data([0x89, 0x50]))
        expected.append(Data("\r\n--TestBoundary--\r\n".utf8))
        XCTAssertEqual(body, expected)
    }

    /// Кейс: файл больше одной порции копирования (2,5 МБ случайных байт).
    /// Ожидание: содержимое скопировано целиком и без искажений между заголовками части и закрывающим разделителем.
    func test_write_largeFile_copiesContentsCompletely() throws {
        let contents = Data((0..<2_500_000).map { _ in UInt8.random(in: .min ... .max) })
        let file = try makeMultipartFile(contents, filename: "big.jpg", mimeType: "image/jpeg")

        let body = try write(parameters: [:], file: file)

        let header = Data("--TestBoundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"big.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let footer = Data("\r\n--TestBoundary--\r\n".utf8)
        XCTAssertEqual(body.count, header.count + contents.count + footer.count)
        XCTAssertEqual(body.prefix(header.count), header)
        XCTAssertEqual(body.dropFirst(header.count).prefix(contents.count), contents)
        XCTAssertEqual(body.suffix(footer.count), footer)
    }

    /// Кейс: имя файла содержит кавычку и перевод строки.
    /// Ожидание: опасные символы заменены на `%22` / `%0A`, заголовок остаётся одной строкой.
    func test_write_escapesQuotesAndLineBreaksInFilename() throws {
        let file = try makeMultipartFile(Data(), filename: "my\"file\n.jpg", mimeType: "image/jpeg")

        let body = try write(parameters: [:], file: file)

        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("filename=\"my%22file%0A.jpg\""), text)
    }

    /// Кейс: загружаемого файла нет на диске.
    /// Ожидание: `write` бросает ошибку.
    func test_write_missingSourceFile_throws() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).jpg")
        let file = MultipartFile(fieldName: "file", filename: "a.jpg", mimeType: "image/jpeg", fileURL: missing)
        let destination = makeDestinationURL()

        XCTAssertThrowsError(try MultipartFormEncoder.write(parameters: [:], file: file, boundary: boundary, to: destination))
    }

    /// Кейс: заголовок `Content-Type` для заданного разделителя.
    /// Ожидание: `multipart/form-data; boundary=<boundary>`.
    func test_contentType_includesBoundary() {
        XCTAssertEqual(MultipartFormEncoder.contentType(boundary: boundary), "multipart/form-data; boundary=TestBoundary")
    }

    // MARK: - Helpers

    /// Создаёт во временной директории файл с содержимым и описывает его как часть формы `file`.
    private func makeMultipartFile(_ contents: Data, filename: String, mimeType: String) throws -> MultipartFile {
        let url = try TemporaryFile.make(contents)
        temporaryFiles.append(url)
        return MultipartFile(fieldName: "file", filename: filename, mimeType: mimeType, fileURL: url)
    }

    /// Записывает тело во временный файл и возвращает его содержимое.
    private func write(parameters: [String: String], file: MultipartFile) throws -> Data {
        let destination = makeDestinationURL()
        try MultipartFormEncoder.write(parameters: parameters, file: file, boundary: boundary, to: destination)
        return try Data(contentsOf: destination)
    }

    /// Уникальный адрес для файла тела, зарегистрированный для удаления.
    private func makeDestinationURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).multipart")
        temporaryFiles.append(url)
        return url
    }
}
