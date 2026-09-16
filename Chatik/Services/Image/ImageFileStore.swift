//
//  ImageFileStore.swift
//  Chatik
//

import UIKit

protocol ImageFileStoreProtocol: Sendable {
    /// Возвращает файл во временной директории, готовый к загрузке на сервер. Файл из галереи возвращается
    /// как есть — оригинал уходит без перекодирования и уменьшения. У снимка с камеры файла нет, поэтому он
    /// кодируется в JPEG в исходном разрешении и записывается во временный файл. Работа выполняется вне main thread.
    func storeForUpload(_ image: PickedImage) async throws -> ImageFile
    /// Удаляет временный файл после загрузки. Отсутствие файла — не ошибка.
    func remove(_ file: ImageFile)
}

/// Ошибки подготовки файла изображения к загрузке.
enum ImageFileStoreError: Error, Equatable {
    /// Снимок не удалось закодировать в JPEG (например, пустое изображение).
    case encodingFailed
    /// Не удалось записать файл во временную директорию.
    case writeFailed
}

/// Без состояния — безопасно вызывать из любого контекста; кодирование и запись уходят в фоновую задачу.
final class ImageFileStore: ImageFileStoreProtocol, Sendable {
    /// Качество JPEG для снимка с камеры. Размер кадра не уменьшается, поэтому качество близкое к максимальному,
    /// но с запасом по лимиту `/files/uploadImage` в 10 МБ для 12-мегапиксельного кадра.
    static let cameraJPEGQuality: CGFloat = 0.9

    /// Файл из галереи отдаёт без изменений; снимок с камеры кодирует и записывает в фоновой задаче —
    /// main thread не блокируется, прелоадер поверх аватара продолжает анимироваться.
    /// - Parameter image: снимок с камеры или файл из галереи.
    func storeForUpload(_ image: PickedImage) async throws -> ImageFile {
        switch image {
        case .file(let file):
            return file
        case .image(let uiImage):
            return try await Task.detached(priority: .userInitiated) { try Self.writeJPEG(uiImage) }.value
        }
    }

    /// Удаляет файл; ошибка удаления (в том числе отсутствие файла) игнорируется.
    /// - Parameter file: временный файл, созданный для загрузки.
    func remove(_ file: ImageFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    /// Кодирует изображение в JPEG в исходном разрешении (ориентация сохраняется в EXIF)
    /// и записывает во временный файл.
    /// - Parameter image: снимок с камеры.
    private static func writeJPEG(_ image: UIImage) throws -> ImageFile {
        guard let data = image.jpegData(compressionQuality: cameraJPEGQuality) else {
            throw ImageFileStoreError.encodingFailed
        }
        let file = ImageFile(url: ImageFile.makeTemporaryURL(type: .jpeg), type: .jpeg)
        do {
            try data.write(to: file.url, options: .atomic)
        } catch {
            throw ImageFileStoreError.writeFailed
        }
        return file
    }
}
