//
//  ImageFileStoreTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ImageFileStoreTests: XCTestCase {
    private let sut = ImageFileStore()
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        TemporaryFile.remove(temporaryFiles)
        temporaryFiles = []
        super.tearDown()
    }

    // MARK: - Снимок с камеры

    /// Кейс: снимок с камеры больше типичного лимита стороны (4096×2048).
    /// Ожидание: во временной директории создан JPEG (сигнатура FF D8) типа `.jpeg`; размеры не изменены — без уменьшения.
    func test_storeForUpload_cameraImage_writesFullSizeJPEGToTemporaryDirectory() async throws {
        let file = try await sut.storeForUpload(.image(.stub(size: CGSize(width: 4096, height: 2048))))
        temporaryFiles.append(file.url)

        let data = try Data(contentsOf: file.url)
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(file.type, .jpeg)
        XCTAssertEqual(file.url.pathExtension, "jpg")
        XCTAssertEqual(file.url.deletingLastPathComponent().standardizedFileURL, FileManager.default.temporaryDirectory.standardizedFileURL)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(decoded.size.width * decoded.scale, 4096)
        XCTAssertEqual(decoded.size.height * decoded.scale, 2048)
    }

    /// Кейс: два снимка подряд.
    /// Ожидание: у каждого свой файл — имена уникальны, предыдущий не перезаписывается.
    func test_storeForUpload_cameraImages_getUniqueFiles() async throws {
        let first = try await sut.storeForUpload(.image(.stub()))
        let second = try await sut.storeForUpload(.image(.stub()))
        temporaryFiles += [first.url, second.url]

        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
    }

    /// Кейс: пустое изображение, которое нельзя закодировать в JPEG.
    /// Ожидание: `ImageFileStoreError.encodingFailed`.
    func test_storeForUpload_emptyImage_throwsEncodingFailed() async {
        do {
            _ = try await sut.storeForUpload(.image(UIImage()))
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ImageFileStoreError, .encodingFailed)
        }
    }

    // MARK: - Файл из галереи

    /// Кейс: файл из галереи (PNG больше 1024 по стороне).
    /// Ожидание: возвращён тот же файл — адрес и формат не изменены, содержимое на диске не тронуто.
    func test_storeForUpload_galleryFile_returnsFileUnchanged() async throws {
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 4096, height: 2048)).pngData())
        let url = try TemporaryFile.make(png, fileExtension: "png")
        temporaryFiles.append(url)
        let original = ImageFile(url: url, type: .png)

        let file = try await sut.storeForUpload(.file(original))

        XCTAssertEqual(file, original)
        XCTAssertEqual(try Data(contentsOf: url), png)
    }

    // MARK: - Удаление

    /// Кейс: удаление существующего временного файла, затем повторное удаление.
    /// Ожидание: файл удалён; повторный вызов для отсутствующего файла не падает.
    func test_remove_deletesFileAndIgnoresMissing() throws {
        let url = try TemporaryFile.make(Data([0xFF, 0xD8]), fileExtension: "jpg")
        let file = ImageFile(url: url, type: .jpeg)

        sut.remove(file)
        sut.remove(file)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
