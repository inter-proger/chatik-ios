//
//  ImageEncoderMock.swift
//  ChatikTests
//

import UIKit
@testable import Chatik

/// Мок кодировщика изображений: отдаёт заданные данные, не трогая само изображение.
final class ImageEncoderMock: ImageEncoderProtocol, @unchecked Sendable {
    var stubbedResult: Result<Data, Error> = .success(Data("JPEG".utf8))
    private(set) var encodeCallCount = 0

    func encodeForUpload(_ image: PickedImage) async throws -> Data {
        encodeCallCount += 1
        return try stubbedResult.get()
    }
}
