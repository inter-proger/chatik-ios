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

    // MARK: - Лимит размера

    /// Кейс: файл из галереи больше лимита.
    /// Ожидание: отдана уменьшенная JPEG-копия, укладывающаяся в лимит; исходный файл удалён —
    /// наружу отдаётся ровно один файл.
    func test_storeForUpload_oversizedGalleryFile_returnsDownscaledCopy() async throws {
        let maxFileSize = 900_000
        let sut = ImageFileStore(maxFileSize: maxFileSize)
        let png = try XCTUnwrap(UIImage.noise(size: CGSize(width: 4096, height: 2048)).pngData())
        let url = try TemporaryFile.make(png, fileExtension: "png")
        temporaryFiles.append(url)
        let original = ImageFile(url: url, type: .png)

        let file = try await sut.storeForUpload(.file(original))
        temporaryFiles.append(file.url)

        XCTAssertNotEqual(file.url, original.url)
        XCTAssertEqual(file.type, .jpeg)
        XCTAssertLessThanOrEqual(try fileSize(of: file.url), maxFileSize)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
    }

    /// Кейс: снимок с камеры, который в исходном разрешении не укладывается в лимит.
    /// Ожидание: отдана уменьшенная копия в пределах лимита, промежуточный полноразмерный файл не остаётся.
    func test_storeForUpload_oversizedCameraImage_returnsDownscaledCopy() async throws {
        let maxFileSize = 900_000
        let sut = ImageFileStore(maxFileSize: maxFileSize)
        let before = try temporaryDirectoryContents()

        let file = try await sut.storeForUpload(.image(.noise(size: CGSize(width: 4096, height: 2048))))
        temporaryFiles.append(file.url)

        XCTAssertLessThanOrEqual(try fileSize(of: file.url), maxFileSize)
        XCTAssertEqual(try temporaryDirectoryContents().subtracting(before), [file.url.lastPathComponent])
    }

    /// Кейс: файл из галереи в пределах лимита.
    /// Ожидание: отдан как есть — уменьшения и перекодирования нет.
    func test_storeForUpload_fileWithinLimit_isNotDownscaled() async throws {
        let sut = ImageFileStore(maxFileSize: 10 * 1024 * 1024)
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 64, height: 64)).pngData())
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

    // MARK: - Helpers

    /// Размер файла в байтах.
    private func fileSize(of url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    /// Имена файлов во временной директории — чтобы поймать промежуточные файлы, оставшиеся после подготовки.
    private func temporaryDirectoryContents() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path))
    }
}
