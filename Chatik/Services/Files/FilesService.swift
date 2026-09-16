//
//  FilesService.swift
//  Chatik
//

import Foundation

protocol FilesServiceProtocol {
    /// Загружает изображение на сервер и возвращает описание созданного файла.
    /// Бросает `FilesServiceError.fileTooLarge` до запроса, если `data` больше допустимого размера.
    /// `onProgress` получает долю отправленных данных от 0 до 1; вызывается не на main.
    func uploadImage(
        data: Data,
        filename: String,
        type: ImageMIMEType,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile
    /// Возвращает описание файла по идентификатору.
    func fetchFile(id: Int) async throws -> RemoteFile
}

/// Ошибки, которые `FilesService` обнаруживает локально, не обращаясь к серверу.
enum FilesServiceError: Error, Equatable {
    /// Файл больше `FilesService.maxImageSize` байт — сервер отклонил бы его кодом 3002, запрос не отправляется.
    case fileTooLarge(maxSize: Int)
}

final class FilesService: FilesServiceProtocol {
    /// Максимальный размер изображения для `/files/uploadImage` — 10 МБ (ограничение сервера).
    static let maxImageSize = 10 * 1024 * 1024

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает изображение через `POST /files/uploadImage` (`multipart/form-data`).
    /// - Parameters:
    ///   - data: содержимое файла размером до `maxImageSize`; иначе `FilesServiceError.fileTooLarge` без запроса.
    ///   - filename: имя файла — сервер сохранит его как имя загруженного файла.
    ///   - type: формат изображения; определяет `Content-Type` файловой части.
    ///   - onProgress: получает долю отправленных данных от 0 до 1 по мере отправки; вызывается не на main.
    func uploadImage(
        data: Data,
        filename: String,
        type: ImageMIMEType,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile {
        guard data.count <= Self.maxImageSize else { throw FilesServiceError.fileTooLarge(maxSize: Self.maxImageSize) }
        let file = MultipartFile(fieldName: FilesEndpoint.uploadFieldName, filename: filename, mimeType: type.rawValue, data: data)
        return try await networkService.upload(FilesEndpoint.uploadImage, file: file, onProgress: onProgress)
    }

    /// Запрашивает файл через `GET /files/get`.
    /// - Parameter id: идентификатор файла.
    func fetchFile(id: Int) async throws -> RemoteFile {
        try await networkService.request(FilesEndpoint.get(fileId: id))
    }
}
