//
//  FilesServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса файлов: возвращает заданный результат и запоминает, что загружали.
final class FilesServiceMock: FilesServiceProtocol {
    var stubbedUpload: Result<RemoteFile, Error> = .failure(NetworkError.missingResponse)
    /// Значения прогресса, которые `uploadImage` сообщает перед возвратом результата.
    var stubbedUploadProgress: [Double] = []
    /// Вызывается внутри `uploadImage` после сообщения прогресса и ожидается до возврата результата —
    /// пока ViewModel гарантированно в состоянии загрузки. `@MainActor`, чтобы читать состояние ViewModel.
    var onUpload: (@MainActor () async -> Void)?
    private(set) var uploads: [(file: ImageFile, filename: String)] = []

    func uploadImage(
        file: ImageFile,
        filename: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteFile {
        uploads.append((file, filename))
        stubbedUploadProgress.forEach(onProgress)
        await onUpload?()
        return try stubbedUpload.get()
    }

    func fetchFile(id: Int) async throws -> RemoteFile {
        try stubbedUpload.get()
    }
}
