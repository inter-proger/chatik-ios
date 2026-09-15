//
//  FilesService.swift
//  Chatik
//

import Foundation

protocol FilesServiceProtocol {
    /// Загружает изображение на сервер и возвращает описание созданного файла.
    func uploadImage(data: Data, filename: String, mimeType: String) async throws -> RemoteFile
    /// Возвращает описание файла по идентификатору.
    func fetchFile(id: Int) async throws -> RemoteFile
}

final class FilesService: FilesServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает изображение через `POST /files/uploadImage` (`multipart/form-data`).
    /// - Parameters:
    ///   - data: содержимое файла; JPEG, PNG или WebP размером до 10 МБ, иначе сервер вернёт 3002 / 3003.
    ///   - filename: имя файла — сервер сохранит его как имя загруженного файла.
    ///   - mimeType: MIME-тип содержимого, например `image/jpeg`.
    func uploadImage(data: Data, filename: String, mimeType: String) async throws -> RemoteFile {
        let file = MultipartFile(fieldName: FilesEndpoint.uploadFieldName, filename: filename, mimeType: mimeType, data: data)
        return try await networkService.upload(FilesEndpoint.uploadImage, file: file)
    }

    /// Запрашивает файл через `GET /files/get`.
    /// - Parameter id: идентификатор файла.
    func fetchFile(id: Int) async throws -> RemoteFile {
        try await networkService.request(FilesEndpoint.get(fileId: id))
    }
}
