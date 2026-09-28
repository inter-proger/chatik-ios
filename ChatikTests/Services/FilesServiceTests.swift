//
//  FilesServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class FilesServiceTests: XCTestCase {
    private var networkService: NetworkServiceMock!
    private var sut: FilesService!
    private var temporaryFiles: [URL] = []

    override func setUp() {
        super.setUp()
        networkService = NetworkServiceMock()
        sut = FilesService(networkService: networkService)
    }

    override func tearDown() {
        TemporaryFile.remove(temporaryFiles)
        temporaryFiles = []
        super.tearDown()
    }

    /// Кейс: загрузка файла изображения.
    /// Ожидание: multipart-запрос на POST /files/uploadImage, файл уходит полем `file` по своему адресу
    /// с переданным именем и MIME-типом своего формата, возвращён файл из ответа.
    func test_uploadImage_uploadsFileToUploadImageEndpoint() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)
        let imageFile = try makeImageFile(size: 4, type: .jpeg)

        let file = try await sut.uploadImage(file: imageFile, filename: "photo.jpg", onProgress: { _ in })

        XCTAssertEqual(file, .stub)
        let endpoint = try XCTUnwrap(networkService.requestedEndpoints.first)
        XCTAssertEqual(endpoint.path, "/files/uploadImage")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters, [:])
        XCTAssertEqual(networkService.uploadedFiles, [
            MultipartFile(fieldName: "file", filename: "photo.jpg", mimeType: "image/jpeg", fileURL: imageFile.url),
        ])
    }

    /// Кейс: сетевой слой сообщает прогресс отправки.
    /// Ожидание: значения доходят до переданного обработчика без изменений и в том же порядке.
    func test_uploadImage_forwardsProgress() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)
        networkService.stubbedUploadProgress = [0.25, 0.5, 1]
        let received = ProgressRecorder()

        _ = try await sut.uploadImage(file: try makeImageFile(size: 0, type: .jpeg), filename: "a.jpg", onProgress: { received.append($0) })

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

    /// Кейс: файл на байт больше `ImageUploadLimits.maxFileSize`.
    /// Ожидание: `FilesServiceError.fileTooLarge` с лимитом, запрос в сеть не уходит.
    func test_uploadImage_tooLarge_throwsWithoutRequest() async throws {
        let imageFile = try makeImageFile(size: ImageUploadLimits.maxFileSize + 1, type: .jpeg)

        do {
            _ = try await sut.uploadImage(file: imageFile, filename: "big.jpg", onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? FilesServiceError, .fileTooLarge(maxSize: ImageUploadLimits.maxFileSize))
        }
        XCTAssertTrue(networkService.requestedEndpoints.isEmpty)
        XCTAssertTrue(networkService.uploadedFiles.isEmpty)
    }

    /// Кейс: файл ровно `ImageUploadLimits.maxFileSize` байт.
    /// Ожидание: лимит включительный — файл отправляется с MIME-типом своего формата.
    func test_uploadImage_exactlyMaxSize_uploads() async throws {
        networkService.stubbedResult = .success(RemoteFile.stub)

        _ = try await sut.uploadImage(file: try makeImageFile(size: ImageUploadLimits.maxFileSize, type: .png), filename: "max.png", onProgress: { _ in })

        XCTAssertEqual(networkService.uploadedFiles.first?.mimeType, "image/png")
    }

    /// Кейс: файла по указанному адресу нет.
    /// Ожидание: `FilesServiceError.fileUnreadable`, запрос в сеть не уходит.
    func test_uploadImage_missingFile_throwsWithoutRequest() async {
        let missing = ImageFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).jpg"), type: .jpeg)

        do {
            _ = try await sut.uploadImage(file: missing, filename: "a.jpg", onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? FilesServiceError, .fileUnreadable)
        }
        XCTAssertTrue(networkService.uploadedFiles.isEmpty)
    }

    /// Кейс: сервер вернул бизнес-ошибку при загрузке (файл слишком большой).
    /// Ожидание: ошибка пробрасывается наружу без изменений.
    func test_uploadImage_propagatesApiError() async throws {
        networkService.stubbedResult = .failure(NetworkError.api(code: NetworkError.Code.fileTooLarge))

        do {
            _ = try await sut.uploadImage(file: try makeImageFile(size: 0, type: .jpeg), filename: "a.jpg", onProgress: { _ in })
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: 3002))
        }
    }

    // MARK: - Helpers

    /// Создаёт во временной директории файл заданного размера (нули) и регистрирует его для удаления.
    private func makeImageFile(size: Int, type: ImageMIMEType) throws -> ImageFile {
        let url = try TemporaryFile.make(Data(count: size), fileExtension: type.fileExtension)
        temporaryFiles.append(url)
        return ImageFile(url: url, type: type)
    }
}
