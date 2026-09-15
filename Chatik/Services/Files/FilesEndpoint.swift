//
//  FilesEndpoint.swift
//  Chatik
//

import Foundation

/// Методы `/files/*`.
enum FilesEndpoint: Endpoint {
    /// POST /files/uploadImage — загрузка изображения (JPEG, PNG, WebP; до 10 МБ). Требует сессии.
    /// Тело — `multipart/form-data`: файл уходит полем `file` через `NetworkServiceProtocol.upload(_:file:)`.
    /// Ответ: `RemoteFile` с `type == .image`.
    case uploadImage
    /// GET /files/get — информация о файле по идентификатору. Ответ: `RemoteFile`.
    case get(fileId: Int)

    /// Имя поля формы, в котором `/files/uploadImage` ожидает файл.
    static let uploadFieldName = "file"

    var path: String {
        switch self {
        case .uploadImage: return "/files/uploadImage"
        case .get: return "/files/get"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .uploadImage: return .post
        case .get: return .get
        }
    }

    var parameters: [String: String] {
        switch self {
        case .uploadImage:
            return [:]
        case let .get(fileId):
            return ["file_id": String(fileId)]
        }
    }

    var headers: [String: String]? { nil }
}
