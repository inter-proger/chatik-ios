//
//  ImageEncoderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ImageEncoderTests: XCTestCase {
    private let sut = ImageEncoder()

    /// Кейс: изображение меньше `maxSide`.
    /// Ожидание: результат — JPEG (сигнатура FF D8), размеры не изменены.
    func test_encodeForUpload_smallImage_encodesJPEGWithoutResizing() async throws {
        let data = try await sut.encodeForUpload(.image(.stub(size: CGSize(width: 300, height: 200))))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(decoded.size.width * decoded.scale, 300)
        XCTAssertEqual(decoded.size.height * decoded.scale, 200)
    }

    /// Кейс: изображение больше `maxSide` по ширине.
    /// Ожидание: большая сторона равна `maxSide`, пропорции сохранены.
    func test_encodeForUpload_largeImage_resizesToMaxSideKeepingAspectRatio() async throws {
        let data = try await sut.encodeForUpload(.image(.stub(size: CGSize(width: 4096, height: 2048))))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width * decoded.scale, ImageEncoder.maxSide)
        XCTAssertEqual(decoded.size.height * decoded.scale, ImageEncoder.maxSide / 2)
    }

    /// Кейс: изображение с scale 3 (как снимок с экрана Retina), в пикселях больше `maxSide`.
    /// Ожидание: ограничение применяется к пикселям, а не к points.
    func test_encodeForUpload_scaledImage_limitsPixelSize() async throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500), format: format).image { _ in }

        let data = try await sut.encodeForUpload(.image(image))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width * decoded.scale, ImageEncoder.maxSide)
        XCTAssertEqual(decoded.size.height * decoded.scale, ImageEncoder.maxSide)
    }

    // MARK: - Файл из галереи

    /// Кейс: PNG-файл больше `maxSide` по ширине.
    /// Ожидание: декодирован сразу в уменьшенном размере — большая сторона `maxSide`, пропорции сохранены, результат JPEG.
    func test_encodeForUpload_largeFile_downsamplesToMaxSide() async throws {
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 4096, height: 2048)).pngData())

        let data = try await sut.encodeForUpload(.file(png))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(decoded.size.width * decoded.scale, ImageEncoder.maxSide)
        XCTAssertEqual(decoded.size.height * decoded.scale, ImageEncoder.maxSide / 2)
    }

    /// Кейс: файл меньше `maxSide`.
    /// Ожидание: размеры не изменены — изображение не увеличивается.
    func test_encodeForUpload_smallFile_keepsSize() async throws {
        let png = try XCTUnwrap(UIImage.stub(size: CGSize(width: 300, height: 200)).pngData())

        let data = try await sut.encodeForUpload(.file(png))

        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width * decoded.scale, 300)
        XCTAssertEqual(decoded.size.height * decoded.scale, 200)
    }

    /// Кейс: содержимое файла — не изображение.
    /// Ожидание: `ImageEncoderError.decodingFailed`.
    func test_encodeForUpload_notAnImage_throwsDecodingFailed() async {
        do {
            _ = try await sut.encodeForUpload(.file(Data("not an image".utf8)))
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? ImageEncoderError, .decodingFailed)
        }
    }
}
