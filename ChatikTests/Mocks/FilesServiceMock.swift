//
//  FilesServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса файлов: возвращает заданный результат и запоминает, что загружали.
final class FilesServiceMock: FilesServiceProtocol {
    var stubbedUpload: Result<RemoteFile, Error> = .failure(NetworkError.missingResponse)
    private(set) var uploads: [(data: Data, filename: String, type: ImageMIMEType)] = []

    func uploadImage(data: Data, filename: String, type: ImageMIMEType) async throws -> RemoteFile {
        uploads.append((data, filename, type))
        return try stubbedUpload.get()
    }

    func fetchFile(id: Int) async throws -> RemoteFile {
        try stubbedUpload.get()
    }
}
