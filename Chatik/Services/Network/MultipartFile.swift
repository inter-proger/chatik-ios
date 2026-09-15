//
//  MultipartFile.swift
//  Chatik
//

import Foundation

/// Файл для загрузки в теле `multipart/form-data`.
struct MultipartFile: Equatable {
    /// Имя поля формы, в котором сервер ожидает файл.
    let fieldName: String
    let filename: String
    let mimeType: String
    let data: Data
}
