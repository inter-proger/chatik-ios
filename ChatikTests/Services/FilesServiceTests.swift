//
//  FilesServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class FilesServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: FilesService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = FilesService(networkService: networkService)
    }

    /// Кейс: загрузка изображения.
    /// Ожидание: multipart-запрос на POST /files/uploadImage, файл уходит полем `file` с переданными именем и MIME-типом,
    /// возвращён файл из ответа.
    func test_uploadImage_uploadsFileToUploadImageEndpoint() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)
        let data = Data("JPEG".utf8)

        let file = try await sut.uploadImage(data: data, filename: "photo.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(file, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/files/uploadImage")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, [:])
        XCTAssertEqual(networkService.uploadedFiles, [
            MultipartFile(fieldName: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: data),
        ])
    }

    /// Кейс: запрос информации о файле.
    /// Ожидание: GET /files/get с `file_id`, возвращён файл из ответа.
    func test_fetchFile_requestsGetEndpointWithFileId() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)

        let file = try await sut.fetchFile(id: 7)

        XCTAssertEqual(file, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/files/get")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["file_id": "7"])
        XCTAssertTrue(networkService.uploadedFiles.isEmpty)
    }

    /// Кейс: сервер вернул бизнес-ошибку при загрузке (файл слишком большой).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_uploadImage_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.fileTooLarge))

        do {
            _ = try await sut.uploadImage(data: Data(), filename: "a.jpg", mimeType: "image/jpeg")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 3002))
        }
    }
}
