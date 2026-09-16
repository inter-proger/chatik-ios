//
//  ImageFileStoreMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок хранилища временных файлов изображений: отдаёт заданный файл, не трогая диск, и запоминает удаления.
final class ImageFileStoreMock: ImageFileStoreProtocol, @unchecked Sendable {
    var stubbedResult: Result<ImageFile, Error> = .success(.stub)
    private(set) var storeCallCount = 0
    private(set) var removedFiles: [ImageFile] = []

    func storeForUpload(_ image: PickedImage) async throws -> ImageFile {
        storeCallCount += 1
        return try stubbedResult.get()
    }

    func remove(_ file: ImageFile) {
        removedFiles.append(file)
    }
}
