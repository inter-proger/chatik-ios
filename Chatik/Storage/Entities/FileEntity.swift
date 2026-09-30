//
//  FileEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о файле на сервере; сырая структура — `RemoteFile`.
@objc(FileEntity)
final class FileEntity: NSManagedObject, StorageEntity {
    @NSManaged var fileId: Int64
    @NSManaged var type: String?
    @NSManaged var url: URL?
    @NSManaged var size: Int64
    @NSManaged var filename: String?
    @NSManaged var fileExtension: String?
    @NSManaged var smallURL: URL?

    static let idKey = "fileId"

    var storageId: Int { Int(fileId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameter file: источник данных.
    func update(from file: RemoteFile) {
        fileId = Int64(file.fileId)
        type = file.type.rawValue
        url = file.url
        size = Int64(file.size)
        filename = file.filename
        fileExtension = file.fileExtension
        smallURL = file.smallURL
    }

    /// Сохраняет файлы в контексте (upsert по `fileId`), не вызывая `save()`.
    /// - Parameters:
    ///   - files: сырые структуры файлов.
    ///   - context: фоновый контекст записи.
    /// - Returns: словарь `fileId → Entity`.
    static func upsert(_ files: [RemoteFile], in context: NSManagedObjectContext) throws -> [Int: FileEntity] {
        try upsert(files, id: \.fileId, in: context) { entity, file in entity.update(from: file) }
    }
}

extension RemoteFile {
    /// Собирает структуру из Entity.
    /// - Parameter entity: запись CoreData.
    /// - Returns: `nil`, если в записи нет обязательных полей.
    init?(entity: FileEntity) {
        guard let rawType = entity.type,
              let url = entity.url,
              let filename = entity.filename,
              let fileExtension = entity.fileExtension else { return nil }
        self.init(
            fileId: Int(entity.fileId),
            type: RemoteFileType(rawValue: rawType) ?? .other,
            url: url,
            size: Int(entity.size),
            filename: filename,
            fileExtension: fileExtension,
            smallURL: entity.smallURL
        )
    }
}
