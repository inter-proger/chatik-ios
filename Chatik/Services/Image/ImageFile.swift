//
//  ImageFile.swift
//  Chatik
//

import Foundation

/// Файл изображения во временной директории, готовый к загрузке на сервер как есть — без перекодирования.
/// Живёт до конца загрузки: после неё удаляется через `ImageFileStoreProtocol.remove(_:)`.
struct ImageFile: Equatable, Sendable {
    let url: URL
    /// Формат файла; определяет `Content-Type` файловой части и расширение имени файла на сервере.
    let type: ImageMIMEType
}
