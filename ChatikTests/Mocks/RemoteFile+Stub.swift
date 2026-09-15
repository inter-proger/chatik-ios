//
//  RemoteFile+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension RemoteFile {
    /// Изображение с уменьшенной копией — типовой ответ `/files/uploadImage`.
    static let stub = RemoteFile(
        fileId: 1,
        type: .image,
        url: URL(string: "http://localhost:8080/static/uploads/photo.jpg")!,
        size: 8293,
        filename: "photo.jpg",
        fileExtension: "jpg",
        smallURL: URL(string: "http://localhost:8080/static/uploads/photo_small.jpg")
    )
}
