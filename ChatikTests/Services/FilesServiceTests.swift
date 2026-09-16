//
//  FilesServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class FilesServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: FilesService!

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = FilesService(networkService: networkService)
    }

    /// Кейс: загрузка изображения.
    /// Ожидание: multipart-запрос на POST /files/uploadImage, файл уходит полем `file` с переданным именем
    /// и MIME-типом выбранного формата, возвращён файл из ответа.
    func test_uploadImage_uploadsFileToUploadImageEndpoint() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)
        let data = Data("JPEG".utf8)

        let file = try await sut.uploadImage(data: data, filename: "photo.jpg", type: .jpeg, onProgress: { _ in })

        XCTAssertEqual(file, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/files/uploadImage")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, [:])
        XCTAssertEqual(networkService.uploadedFiles, [
            MultipartFile(fieldName: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: data),
        ])
    }

    /// Кейс: сетевой слой сообщает прогресс отправки.
    /// Ожидание: значения доходят до переданного обработчика без изменений и в том же порядке.
    func test_uploadImage_forwardsProgress() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)
        networkService.stubbedUploadProgress = [0.25, 0.5, 1]
        let received = ProgressRecorder()

        _ = try await sut.uploadImage(data: Data(), filename: "a.jpg", type: .jpeg, onProgress: { received.append($0) })

        XCTAssertEqual(received.values, [0.25, 0.5, 1])
    }

    /// Кейс: запрос информации о файле.
    /// Ожидание: GET /files/get с `fileId`, возвращён файл из ответа.
    func test_fetchFile_requestsGetEndpointWithFileId() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)

        let file = try await sut.fetchFile(id: 7)

        XCTAssertEqual(file, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/files/get")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters, ["fileId": "7"])
        XCTAssertTrue(networkService.uploadedFiles.isEmpty)
    }

    /// Кейс: файл на байт больше `maxImageSize`.
    /// Ожидание: `FilesServiceError.fileTooLarge` с лимитом, запрос в сеть не уходит.
    func test_uploadImage_tooLarge_throwsWithoutRequest() async {
        let data = Data(count: FilesService.maxImageSize + 1)

        do {
            _ = try await sut.uploadImage(data: data, filename: "big.jpg", type: .jpeg, onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? FilesServiceError, .fileTooLarge(maxSize: FilesService.maxImageSize))
        }
        XCTAssertTrue(networkService.requestedEndpoints.isEmpty)
        XCTAssertTrue(networkService.uploadedFiles.isEmpty)
    }

    /// Кейс: файл ровно `maxImageSize` байт.
    /// Ожидание: лимит включительный — файл отправляется.
    func test_uploadImage_exactlyMaxSize_uploads() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)

        _ = try await sut.uploadImage(data: Data(count: FilesService.maxImageSize), filename: "max.png", type: .png, onProgress: { _ in })

        XCTAssertEqual(networkService.uploadedFiles.first?.mimeType, "image/png")
    }

    /// Кейс: сервер вернул бизнес-ошибку при загрузке (файл слишком большой).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_uploadImage_propagatesApiError() async {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.fileTooLarge))

        do {
            _ = try await sut.uploadImage(data: Data(), filename: "a.jpg", type: .jpeg, onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 3002))
        }
    }
}
