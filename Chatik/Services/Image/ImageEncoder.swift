//
//  ImageEncoder.swift
//  Chatik
//

import ImageIO
import UIKit

protocol ImageEncoderProtocol: Sendable {
    /// Готовит изображение к загрузке на сервер: уменьшает до `ImageEncoder.maxSide` по большей стороне
    /// и кодирует в JPEG. Ориентация из EXIF «запекается» в пиксели. Работа выполняется вне main thread.
    func encodeForUpload(_ image: PickedImage) async throws -> Data
}

/// Ошибки подготовки изображения к загрузке.
enum ImageEncoderError: Error, Equatable {
    /// Содержимое файла не удалось прочитать как изображение.
    case decodingFailed
    /// `UIImage` не удалось закодировать в JPEG (например, пустое изображение).
    case encodingFailed
}

/// Без состояния — безопасно вызывать из любого контекста; кодирование уходит в фоновую задачу.
final class ImageEncoder: ImageEncoderProtocol, Sendable {
    /// Максимальный размер большей стороны в пикселях: аватар крупнее не нужен, а лимит `/files/uploadImage` — 10 МБ.
    static let maxSide: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.85

    /// Уменьшает изображение до `maxSide` и кодирует в JPEG в фоновой задаче — main thread не блокируется
    /// на декодирование и перерисовку, прелоадер поверх аватара продолжает анимироваться.
    /// - Parameter image: снимок с камеры или содержимое файла из галереи.
    func encodeForUpload(_ image: PickedImage) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try Self.encode(image) }.value
    }

    /// Приводит изображение к размеру не больше `maxSide` и кодирует в JPEG качеством `jpegQuality`.
    /// - Parameter image: исходное изображение.
    private static func encode(_ image: PickedImage) throws -> Data {
        let resized: UIImage
        switch image {
        case .image(let uiImage): resized = render(uiImage, fitting: maxSide)
        case .file(let data): resized = try downsample(data, fitting: maxSide)
        }
        guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else {
            throw ImageEncoderError.encodingFailed
        }
        return jpeg
    }

    /// Перерисовывает уже декодированное изображение так, чтобы большая сторона в пикселях не превышала `maxSide`;
    /// меньшее изображение не увеличивается. Перерисовка также нормализует ориентацию.
    /// - Parameters:
    ///   - image: исходное изображение.
    ///   - maxSide: ограничение большей стороны в пикселях.
    private static func render(_ image: UIImage, fitting maxSide: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        let ratio = longest > maxSide ? maxSide / longest : 1
        let targetSize = CGSize(width: (pixelSize.width * ratio).rounded(.down), height: (pixelSize.height * ratio).rounded(.down))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Декодирует файл сразу в уменьшенном размере через ImageIO — полный кадр (12–48 Мп у HEIC с iPhone)
    /// в память не попадает. Меньшее изображение не увеличивается; ориентация из EXIF применяется к пикселям.
    /// - Parameters:
    ///   - data: содержимое файла изображения.
    ///   - maxSide: ограничение большей стороны в пикселях.
    private static func downsample(_ data: Data, fitting maxSide: CGFloat) throws -> UIImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageEncoderError.decodingFailed
        }
        return UIImage(cgImage: cgImage)
    }
}
