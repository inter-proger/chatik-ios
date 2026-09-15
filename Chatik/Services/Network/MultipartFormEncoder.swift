//
//  MultipartFormEncoder.swift
//  Chatik
//

import Foundation

/// Собирает тело запроса формата `multipart/form-data`: текстовые поля и один файл.
enum MultipartFormEncoder {
    private static let lineBreak = "\r\n"

    /// Значение заголовка `Content-Type` для тела с указанным разделителем.
    /// - Parameter boundary: разделитель частей.
    static func contentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Собирает тело: сначала текстовые поля (отсортированы по ключу), затем файл, затем закрывающий разделитель.
    /// - Parameters:
    ///   - parameters: текстовые поля формы.
    ///   - file: файл формы.
    ///   - boundary: разделитель частей; должен совпадать с переданным в `Content-Type`.
    static func encode(parameters: [String: String], file: MultipartFile, boundary: String) -> Data {
        var body = Data()
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            body.append(textPart(name: key, value: value, boundary: boundary))
        }
        body.append(filePart(file, boundary: boundary))
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }

    /// Часть с текстовым полем.
    private static func textPart(name: String, value: String, boundary: String) -> String {
        "--\(boundary)\(lineBreak)"
            + "Content-Disposition: form-data; name=\"\(escape(name))\"\(lineBreak)\(lineBreak)"
            + "\(value)\(lineBreak)"
    }

    /// Часть с файлом: заголовки, бинарные данные, перевод строки.
    private static func filePart(_ file: MultipartFile, boundary: String) -> Data {
        var part = Data()
        part.append("--\(boundary)\(lineBreak)")
        part.append("Content-Disposition: form-data; name=\"\(escape(file.fieldName))\"; filename=\"\(escape(file.filename))\"\(lineBreak)")
        part.append("Content-Type: \(file.mimeType)\(lineBreak)\(lineBreak)")
        part.append(file.data)
        part.append(lineBreak)
        return part
    }

    /// Экранирует символы, ломающие заголовок `Content-Disposition` (кавычки и переводы строк).
    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}

private extension Data {
    /// Добавляет строку в кодировке UTF-8.
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
