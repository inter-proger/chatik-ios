//
//  ImageFileStore.swift
//  Chatik
//

import ImageIO
import UIKit

protocol ImageFileStoreProtocol: Sendable {
    /// Возвращает файл во временной директории, готовый к загрузке на сервер. Файл из галереи возвращается
    /// как есть — оригинал уходит без перекодирования. У снимка с камеры файла нет, поэтому он кодируется
    /// в JPEG в исходном разрешении и записывается во временный файл. Файл, не уложившийся в лимит размера,
    /// заменяется уменьшенной JPEG-копией. Работа выполняется вне main thread.
    func storeForUpload(_ image: PickedImage) async throws -> ImageFile
    /// Удаляет временный файл после загрузки. Отсутствие файла — не ошибка.
    func remove(_ file: ImageFile)
}

extension ImageFileStore {
    /// Уникальный адрес для нового файла во временной директории (сам файл не создаётся).
    /// Здесь же — запись и удаление таких файлов: политика временных файлов собрана в хранилище,
    /// а `ImageFile` остаётся описанием готового файла.
    /// - Parameter type: формат изображения — задаёт расширение файла.
    static func makeTemporaryURL(type: ImageMIMEType) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(type.fileExtension)")
    }
}

/// Ошибки подготовки файла изображения к загрузке.
enum ImageFileStoreError: Error, Equatable {
    /// Изображение не удалось закодировать в JPEG (например, пустое изображение).
    case encodingFailed
    /// Файл не удалось прочитать как изображение при уменьшении.
    case decodingFailed
    /// Не удалось записать файл во временную директорию.
    case writeFailed
    /// Не удалось прочитать размер файла.
    case readFailed
}

/// Без состояния — безопасно вызывать из любого контекста; кодирование и запись уходят в фоновую задачу.
final class ImageFileStore: ImageFileStoreProtocol, Sendable {
    /// Качество JPEG для снимка с камеры. Размер кадра не уменьшается, поэтому качество близкое к максимальному.
    static let cameraJPEGQuality: CGFloat = 0.9
    /// Качество JPEG для уменьшенной копии — файла, не уложившегося в лимит.
    static let downscaledJPEGQuality: CGFloat = 0.85
    /// Стороны, до которых по очереди уменьшается не уложившийся в лимит файл: берётся первая подходящая.
    static let downscaleSides: [CGFloat] = [2048, 1024]

    /// Максимальный размер файла, который примет сервер.
    private let maxFileSize: Int

    /// - Parameter maxFileSize: лимит размера файла; по умолчанию — лимит `/files/uploadImage`.
    ///   Файл крупнее заменяется уменьшенной копией, чтобы загрузка не упиралась в ошибку 3002.
    init(maxFileSize: Int = FilesService.maxImageSize) {
        self.maxFileSize = maxFileSize
    }

    /// Готовит файл в фоновой задаче — main thread не блокируется на кодировании и записи,
    /// прелоадер поверх аватара продолжает анимироваться.
    /// - Parameter image: снимок с камеры или файл из галереи.
    func storeForUpload(_ image: PickedImage) async throws -> ImageFile {
        let maxFileSize = maxFileSize
        return try await Task.detached(priority: .userInitiated) {
            try Self.prepareForUpload(image, maxFileSize: maxFileSize)
        }.value
    }

    /// Удаляет файл; ошибка удаления (в том числе отсутствие файла) игнорируется.
    /// - Parameter file: временный файл, созданный для загрузки.
    func remove(_ file: ImageFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    // MARK: - Private

    /// Приводит выбранное изображение к файлу, укладывающемуся в лимит.
    /// - Parameters:
    ///   - image: снимок с камеры или файл из галереи.
    ///   - maxFileSize: лимит размера файла.
    private static func prepareForUpload(_ image: PickedImage, maxFileSize: Int) throws -> ImageFile {
        switch image {
        case .file(let file):
            return try fit(file, maxFileSize: maxFileSize)
        case .image(let uiImage):
            return try fit(try writeJPEG(uiImage), maxFileSize: maxFileSize)
        }
    }

    /// Возвращает файл, укладывающийся в лимит: подходящий — как есть, иначе уменьшенную JPEG-копию.
    /// Заменённый файл удаляется — наружу отдаётся ровно один файл, и удалять вызывающему нужно только его.
    /// - Parameters:
    ///   - file: исходный файл.
    ///   - maxFileSize: лимит размера файла.
    private static func fit(_ file: ImageFile, maxFileSize: Int) throws -> ImageFile {
        guard try fileSize(of: file.url) > maxFileSize else { return file }

        var reduced: ImageFile?
        for side in downscaleSides {
            let candidate = try downscaledJPEG(of: file, maxSide: side)
            reduced.map { try? FileManager.default.removeItem(at: $0.url) }
            reduced = candidate
            if try fileSize(of: candidate.url) <= maxFileSize { break }
        }
        guard let reduced else { return file }

        try? FileManager.default.removeItem(at: file.url)
        return reduced
    }

    /// Кодирует изображение в JPEG в исходном разрешении (ориентация сохраняется в EXIF)
    /// и записывает во временный файл.
    /// - Parameter image: снимок с камеры.
    private static func writeJPEG(_ image: UIImage) throws -> ImageFile {
        guard let data = image.jpegData(compressionQuality: cameraJPEGQuality) else {
            throw ImageFileStoreError.encodingFailed
        }
        return try write(data)
    }

    /// Декодирует файл сразу в уменьшенном размере через ImageIO — полный кадр в память не попадает —
    /// и записывает JPEG-копию во временный файл.
    /// - Parameters:
    ///   - file: исходный файл изображения.
    ///   - maxSide: ограничение большей стороны в пикселях.
    private static func downscaledJPEG(of file: ImageFile, maxSide: CGFloat) throws -> ImageFile {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageFileStoreError.decodingFailed
        }
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: downscaledJPEGQuality) else {
            throw ImageFileStoreError.encodingFailed
        }
        return try write(data)
    }

    /// Записывает JPEG во временный файл под уникальным именем.
    /// - Parameter data: содержимое файла.
    private static func write(_ data: Data) throws -> ImageFile {
        let file = ImageFile(url: makeTemporaryURL(type: .jpeg), type: .jpeg)
        do {
            try data.write(to: file.url, options: .atomic)
        } catch {
            throw ImageFileStoreError.writeFailed
        }
        return file
    }

    /// Размер файла в байтах по метаданным файловой системы.
    /// - Parameter url: адрес локального файла.
    private static func fileSize(of url: URL) throws -> Int {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw ImageFileStoreError.readFailed
        }
        return size
    }
}
