//
//  MultipartFormEncoder.swift
//  Chatik
//

import Foundation

/// Собирает тело запроса формата `multipart/form-data` — текстовые поля и один файл — в файл на диске,
/// чтобы содержимое загружаемого файла не попадало в память целиком и тело можно было отправить из файла.
enum MultipartFormEncoder {
    private static let lineBreak = "\r\n"
    /// Размер порции при копировании файла в тело.
    private static let chunkSize = 1024 * 1024

    /// Значение заголовка `Content-Type` для тела с указанным разделителем.
    /// - Parameter boundary: разделитель частей.
    static func contentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Записывает тело в файл `destination` (существующий файл перезаписывается): сначала текстовые поля
    /// (отсортированы по ключу), затем файл — его содержимое копируется порциями, — затем закрывающий разделитель.
    /// - Parameters:
    ///   - parameters: текстовые поля формы.
    ///   - file: файл формы.
    ///   - boundary: разделитель частей; должен совпадать с переданным в `Content-Type`.
    ///   - destination: куда записать тело.
    /// - Throws: ошибки файловой системы — если не удалось создать `destination` или прочитать `file.fileURL`.
    static func write(parameters: [String: String], file: MultipartFile, boundary: String, to destination: URL) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var head = Data()
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            head.append(textPart(name: key, value: value, boundary: boundary))
        }
        head.append(filePartHeader(file, boundary: boundary))
        try output.write(contentsOf: head)
        try copyContents(of: file.fileURL, to: output)
        try output.write(contentsOf: Data("\(lineBreak)--\(boundary)--\(lineBreak)".utf8))
    }

    /// Часть с текстовым полем.
    private static func textPart(name: String, value: String, boundary: String) -> String {
        "--\(boundary)\(lineBreak)"
            + "Content-Disposition: form-data; name=\"\(escape(name))\"\(lineBreak)\(lineBreak)"
            + "\(value)\(lineBreak)"
    }

    /// Заголовки файловой части — до бинарных данных.
    private static func filePartHeader(_ file: MultipartFile, boundary: String) -> String {
        "--\(boundary)\(lineBreak)"
            + "Content-Disposition: form-data; name=\"\(escape(file.fieldName))\"; filename=\"\(escape(file.filename))\"\(lineBreak)"
            + "Content-Type: \(file.mimeType)\(lineBreak)\(lineBreak)"
    }

    /// Копирует содержимое файла в `output` порциями по `chunkSize`.
    private static func copyContents(of url: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
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
