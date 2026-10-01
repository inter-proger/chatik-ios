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

    // MARK: - Лимит числа пикселей

    /// Кейс: файл из галереи с числом пикселей больше лимита (4096×2048 при лимите 2 мегапикселя).
    /// Ожидание: отдана уменьшенная JPEG-копия в пределах лимита с сохранённым соотношением сторон;
    /// исходный файл удалён.
    func test_storeForUpload_tooManyPixelsGalleryFile_returnsDownscaledCopy() async throws {
        let maxPixels = 2_000_000
        let sut = ImageFileStore(maxPixels: maxPixels)
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 4096, height: 2048)).pngData())
        let url = try TemporaryFile.make(png, fileExtension: "png")
        temporaryFiles.append(url)
        let original = ImageFile(url: url, type: .png)

        let file = try await sut.storeForUpload(.file(original))
        temporaryFiles.append(file.url)

        let decoded = try XCTUnwrap(UIImage(data: try Data(contentsOf: file.url)))
        let size = CGSize(width: decoded.size.width * decoded.scale, height: decoded.size.height * decoded.scale)
        XCTAssertEqual(file.type, .jpeg)
        XCTAssertLessThanOrEqual(Int(size.width * size.height), maxPixels)
        XCTAssertEqual(size.width / size.height, 2, accuracy: 0.01)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
    }

    /// Кейс: снимок с камеры с числом пикселей больше лимита.
    /// Ожидание: отдана уменьшенная копия в пределах лимита, промежуточный полноразмерный файл не остаётся.
    func test_storeForUpload_tooManyPixelsCameraImage_returnsDownscaledCopy() async throws {
        let maxPixels = 2_000_000
        let sut = ImageFileStore(maxPixels: maxPixels)
        let before = try temporaryDirectoryContents()

        let file = try await sut.storeForUpload(.image(.stub(size: CGSize(width: 4096, height: 2048))))
        temporaryFiles.append(file.url)

        let decoded = try XCTUnwrap(UIImage(data: try Data(contentsOf: file.url)))
        XCTAssertLessThanOrEqual(Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale), maxPixels)
        XCTAssertEqual(try temporaryDirectoryContents().subtracting(before), [file.url.lastPathComponent])
    }

    /// Кейс: файл в пределах лимита пикселей и лимита размера.
    /// Ожидание: отдан как есть — уменьшения и перекодирования нет.
    func test_storeForUpload_fileWithinPixelLimit_isNotDownscaled() async throws {
        let sut = ImageFileStore(maxPixels: 25_000_000)
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 4096, height: 2048)).pngData())
        let url = try TemporaryFile.make(png, fileExtension: "png")
        temporaryFiles.append(url)
        let original = ImageFile(url: url, type: .png)

        let file = try await sut.storeForUpload(.file(original))

        XCTAssertEqual(file, original)
        XCTAssertEqual(try Data(contentsOf: url), png)
    }

    /// Кейс: файл, который не проходит оба лимита сразу (шум сжимается плохо, поэтому и после
    /// приведения к лимиту пикселей файл остаётся слишком большим).
    /// Ожидание: итоговый файл укладывается и в лимит размера, и в лимит пикселей.
    func test_storeForUpload_oversizedAndTooManyPixels_fitsBothLimits() async throws {
        let maxFileSize = 600_000
        let maxPixels = 2_000_000
        let sut = ImageFileStore(maxFileSize: maxFileSize, maxPixels: maxPixels)
        let png = try XCTUnwrap(UIImage.noise(size: CGSize(width: 4096, height: 2048)).pngData())
        let url = try TemporaryFile.make(png, fileExtension: "png")
        temporaryFiles.append(url)

        let file = try await sut.storeForUpload(.file(ImageFile(url: url, type: .png)))
        temporaryFiles.append(file.url)

        let decoded = try XCTUnwrap(UIImage(data: try Data(contentsOf: file.url)))
        XCTAssertLessThanOrEqual(try fileSize(of: file.url), maxFileSize)
        XCTAssertLessThanOrEqual(Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale), maxPixels)
    }

    /// Кейс: файл не является изображением — размеры кадра прочитать нельзя.
    /// Ожидание: `ImageFileStoreError.decodingFailed`.
    func test_storeForUpload_notAnImage_throwsDecodingFailed() async throws {
        let url = try TemporaryFile.make(Data("not an image".utf8), fileExtension: "jpg")
        temporaryFiles.append(url)

        do {
            _ = try await sut.storeForUpload(.file(ImageFile(url: url, type: .jpeg)))
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ImageFileStoreError, .decodingFailed)
        }
    }

    /// Кейс: подготовка файла завершилась ошибкой (содержимое — не изображение).
    /// Ожидание: во временной директории не остаётся новых файлов — неудачная попытка не копит мусор.
    func test_storeForUpload_failure_leavesNoTemporaryFiles() async throws {
        let url = try TemporaryFile.make(Data("not an image".utf8), fileExtension: "jpg")
        temporaryFiles.append(url)
        let before = try temporaryDirectoryContents()

        do {
            _ = try await sut.storeForUpload(.file(ImageFile(url: url, type: .jpeg)))
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ImageFileStoreError, .decodingFailed)
        }

        XCTAssertEqual(try temporaryDirectoryContents(), before)
    }

    // MARK: - Удаление

    /// Кейс: удаление существующего временного файла, затем повторное удаление.
    /// Ожидание: файл удалён (в фоне, поэтому проверка ждёт); повторный вызов для отсутствующего файла не падает.
    @MainActor
    func test_remove_deletesFileAndIgnoresMissing() async throws {
        let url = try TemporaryFile.make(Data([0xFF, 0xD8]), fileExtension: "jpg")
        let file = ImageFile(url: url, type: .jpeg)

        sut.remove(file)
        sut.remove(file)

        await waitUntil { !FileManager.default.fileExists(atPath: url.path) }
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
