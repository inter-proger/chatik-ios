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

    /// Разбирает плоские поля и вложенный объект `data`. Отсутствующий или `null` `data`, как и отсутствующий
    /// `small_url`, не считается ошибкой; `data` не-объект (строка, массив) — ошибка декодирования.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileId = try container.decode(Int.self, forKey: .fileId)
        type = try container.decode(RemoteFileType.self, forKey: .type)
        url = try container.decode(URL.self, forKey: .url)
        size = try container.decode(Int.self, forKey: .size)
        filename = try container.decode(String.self, forKey: .filename)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
        smallURL = try Self.dataContainer(in: container)?.decodeIfPresent(URL.self, forKey: .smallURL)
    }

    /// Контейнер объекта `data`, если он есть и не `null`.
    /// - Parameter container: контейнер верхнего уровня файла.
    private static func dataContainer(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> KeyedDecodingContainer<DataCodingKeys>? {
        guard container.contains(.data), try !container.decodeNil(forKey: .data) else { return nil }
        return try container.nestedContainer(keyedBy: DataCodingKeys.self, forKey: .data)
    }
}
