//
//  FilesService.swift
//  Chatik
//

import Foundation

protocol FilesServiceProtocol {
    /// Загружает файл изображения на сервер как есть и возвращает описание созданного файла.
    /// Бросает `FilesServiceError.fileTooLarge` до запроса, если файл больше допустимого размера,
    /// и `FilesServiceError.fileUnreadable`, если файл недоступен.
    /// `onProgress` получает долю отправленных данных от 0 до 1; вызывается не на main.
    func uploadImage(
        file: ImageFile,
        filename: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile
    /// Возвращает описание файла по идентификатору.
    func fetchFile(id: Int) async throws -> RemoteFile
}

/// Ошибки, которые `FilesService` обнаруживает локально, не обращаясь к серверу.
enum FilesServiceError: Error, Equatable {
    /// Файл больше `ImageUploadLimits.maxFileSize` байт — сервер отклонил бы его кодом 3002, запрос не отправляется.
    case fileTooLarge(maxSize: Int)
    /// Файл по указанному адресу не существует или его размер не удалось прочитать; запрос не отправляется.
    case fileUnreadable
}

final class FilesService: FilesServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает изображение через `POST /files/uploadImage` (`multipart/form-data`) из файла — содержимое
    /// уходит без изменений и в память целиком не читается.
    /// - Parameters:
    ///   - file: файл размером до `ImageUploadLimits.maxFileSize`; иначе `FilesServiceError.fileTooLarge` без запроса.
    ///   - filename: имя файла — сервер сохранит его как имя загруженного файла.
    ///   - onProgress: получает долю отправленных данных от 0 до 1 по мере отправки; вызывается не на main.
    func uploadImage(
        file: ImageFile,
        filename: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile {
        guard try fileSize(of: file.url) <= ImageUploadLimits.maxFileSize else {
            throw FilesServiceError.fileTooLarge(maxSize: ImageUploadLimits.maxFileSize)
        }
        let part = MultipartFile(fieldName: FilesEndpoint.uploadFieldName, filename: filename, mimeType: file.type.rawValue, fileURL: file.url)
        return try await networkService.upload(FilesEndpoint.uploadImage, file: part, onProgress: onProgress)
    }

    /// Запрашивает файл через `GET /files/get`.
    /// - Parameter id: идентификатор файла.
    func fetchFile(id: Int) async throws -> RemoteFile {
        try await networkService.request(FilesEndpoint.get(fileId: id))
    }

    /// Размер файла в байтах по метаданным файловой системы.
    /// - Parameter url: адрес локального файла.
    /// - Throws: `FilesServiceError.fileUnreadable`, если файла нет или размер недоступен.
    private func fileSize(of url: URL) throws -> Int {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw FilesServiceError.fileUnreadable
        }
        return size
    }
}
