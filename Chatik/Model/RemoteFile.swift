//
//  RemoteFile.swift
//  Chatik
//

import Foundation

/// Тип файла на сервере. Список будет расширяться: неизвестные значения читаются как `.other`.
enum RemoteFileType: String, Decodable, Equatable {
    case image
    case other

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = RemoteFileType(rawValue: rawValue) ?? .other
    }
}

/// Объект `File` из API — файл, загруженный на сервер.
struct RemoteFile: Decodable, Equatable {
    let fileId: Int
    let type: RemoteFileType
    let url: URL
    /// Размер в байтах.
    let size: Int
    let filename: String
    /// Расширение файла; если расширения нет — `"file"`.
    let fileExtension: String
    /// Уменьшенная копия (не более 200 px по меньшей стороне) — только для `type == .image`.
    let smallURL: URL?

    private enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case type
        case url
        case size
        case filename
        case fileExtension = "extension"
        case data
    }

    /// Дополнительные поля `data`, состав зависит от `type`.
    private enum DataCodingKeys: String, CodingKey {
        case smallURL = "small_url"
    }

    init(fileId: Int, type: RemoteFileType, url: URL, size: Int, filename: String, fileExtension: String, smallURL: URL?) {
        self.fileId = fileId
        self.type = type
        self.url = url
        self.size = size
        self.filename = filename
        self.fileExtension = fileExtension
        self.smallURL = smallURL
    }

    /// Разбирает плоские поля и вложенный объект `data`; отсутствующий `data` или `small_url` не считается ошибкой.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileId = try container.decode(Int.self, forKey: .fileId)
        type = try container.decode(RemoteFileType.self, forKey: .type)
        url = try container.decode(URL.self, forKey: .url)
        size = try container.decode(Int.self, forKey: .size)
        filename = try container.decode(String.self, forKey: .filename)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
        let data = try? container.nestedContainer(keyedBy: DataCodingKeys.self, forKey: .data)
        smallURL = try data?.decodeIfPresent(URL.self, forKey: .smallURL)
    }
}
