//
//  TemporaryFile.swift
//  ChatikTests
//

import Foundation

/// Файл во временной директории, создаваемый тестом; удаляется в `tearDown` через `remove()`.
enum TemporaryFile {
    /// Создаёт файл с указанным содержимым под уникальным именем.
    /// - Parameters:
    ///   - data: содержимое файла.
    ///   - fileExtension: расширение имени файла.
    static func make(_ data: Data, fileExtension: String = "bin") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try data.write(to: url)
        return url
    }

    /// Удаляет файлы, если они есть.
    static func remove(_ urls: [URL]) {
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
