//
//  FileStorageService.swift
//  Chatik
//

import CoreData

protocol FileStorageServiceProtocol {
    /// Сохраняет файл (upsert по `fileId`).
    func save(file: RemoteFile) async throws
    /// Сохраняет список файлов одним фоновым контекстом (upsert по `fileId`).
    func save(files: [RemoteFile]) async throws
    /// Возвращает все сохранённые файлы.
    func fetchAll() async throws -> [RemoteFile]
    /// Ищет файл по идентификатору.
    func find(byId id: Int) async throws -> RemoteFile?
    /// Удаляет файл по идентификатору, если он найден.
    func delete(byId id: Int) async throws
}

/// Хранилище файлов в CoreData. Все операции выполняются в фоновых контекстах.
final class FileStorageService: FileStorageServiceProtocol {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    /// Сохраняет один файл: обновляет существующую запись с тем же `fileId` или создаёт новую.
    /// - Parameter file: сырая структура файла.
    func save(file: RemoteFile) async throws {
        try await save(files: [file])
    }

    /// Сохраняет список файлов одним фоновым контекстом (upsert по `fileId`).
    /// - Parameter files: сырые структуры; повторы `fileId` внутри списка схлопываются в одну запись.
    func save(files: [RemoteFile]) async throws {
        guard !files.isEmpty else { return }
        try await container.performWrite { context in
            _ = try FileEntity.upsert(files, in: context)
            try context.save()
        }
    }

    /// Возвращает все сохранённые файлы; записи с битыми данными пропускаются.
    func fetchAll() async throws -> [RemoteFile] {
        try await container.performBackgroundTask { context in
            try context.fetch(FileEntity.makeFetchRequest()).compactMap(RemoteFile.init(entity:))
        }
    }

    /// Ищет файл по идентификатору.
    /// - Parameter id: идентификатор искомого файла.
    func find(byId id: Int) async throws -> RemoteFile? {
        try await container.performBackgroundTask { context in
            try context.fetch(FileEntity.makeFetchRequest(id: id)).first.flatMap(RemoteFile.init(entity:))
        }
    }

    /// Удаляет файл по идентификатору; ссылки на него у пользователей и переписок обнуляются.
    /// - Parameter id: идентификатор удаляемого файла.
    func delete(byId id: Int) async throws {
        try await container.performWrite { context in
            guard let entity = try context.fetch(FileEntity.makeFetchRequest(id: id)).first else { return }
            context.delete(entity)
            try context.save()
        }
    }
}
