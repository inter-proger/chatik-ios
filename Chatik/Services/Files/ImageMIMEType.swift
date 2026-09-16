//
//  ImageMIMEType.swift
//  Chatik
//

import UniformTypeIdentifiers

/// Форматы изображений, которые принимает `/files/uploadImage`. Другие типы сервер отклоняет кодом 3003,
/// поэтому выбор ограничен на уровне типа, а не строкой MIME.
enum ImageMIMEType: String, CaseIterable, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case webp = "image/webp"

    /// Расширение файла для имени при загрузке.
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        }
    }

    /// Системный тип содержимого — для запроса файла этого формата у `PhotosPicker`.
    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .webp: return .webP
        }
    }
}
