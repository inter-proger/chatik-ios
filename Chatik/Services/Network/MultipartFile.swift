//
//  MultipartFile.swift
//  Chatik
//

import Foundation

/// Файл для загрузки в теле `multipart/form-data`. Содержимое не читается в память: оно копируется
/// из `fileURL` в тело запроса потоком, и тело уходит upload-задачей из файла.
struct MultipartFile: Equatable {
    /// Имя поля формы, в котором сервер ожидает файл.
    let fieldName: String
    let filename: String
    let mimeType: String
    /// Локальный файл с содержимым; должен существовать до завершения отправки.
    let fileURL: URL
}
