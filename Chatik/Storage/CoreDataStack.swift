//
//  CoreDataStack.swift
//  Chatik
//

import CoreData
import os

/// Фабрика контейнеров CoreData. Контейнер передаётся в storage-сервисы через `init`
/// (в приложении — из `DIContainer`).
enum CoreDataStack {
    /// Модель загружается один раз на процесс и переиспользуется всеми контейнерами: иначе в тестах
    /// несколько моделей претендуют на одни и те же классы Entity.
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: UserEntity.self).url(forResource: "Chatik", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Не найдена модель CoreData Chatik.momd")
        }
        return model
    }()

    /// Создаёт контейнер CoreData.
    /// - Parameter inMemory: `true` — хранилище не пишется на диск (для тестов и превью).
    static func makeContainer(inMemory: Bool = false) -> NSPersistentContainer {
        // SQLite по адресу /dev/null, а не NSInMemoryStoreType: так в тестах работают
        // unique constraints и NSBatchDeleteRequest, как в настоящем хранилище.
        makeContainer(storeURL: inMemory ? URL(fileURLWithPath: "/dev/null") : nil)
    }

    /// Создаёт контейнер CoreData над хранилищем по указанному адресу.
    /// БД — только кэш серверных данных: если хранилище не открылось (файл повреждён, автоматическая миграция
    /// не справилась), оно удаляется и создаётся заново, а не роняет приложение на каждом запуске.
    /// - Parameter storeURL: адрес файла хранилища; `nil` — адрес по умолчанию в каталоге приложения.
    static func makeContainer(storeURL: URL?) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Chatik", managedObjectModel: model)
        if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        guard let error = loadStores(of: container) else { return container }

        Logger.storage.error("Не удалось открыть БД, она будет создана заново: \(String(describing: error), privacy: .public)")
        destroyStores(of: container)
        if let error = loadStores(of: container) {
            fatalError("Не удалось создать хранилище CoreData: \(error)")
        }
        return container
    }

    /// Загружает хранилища контейнера. Загрузка синхронная: описания создаются контейнером
    /// с `shouldAddStoreAsynchronously == false`.
    /// - Parameter container: контейнер, хранилища которого загружаются.
    /// - Returns: первая ошибка загрузки; `nil` — все хранилища открыты.
    private static func loadStores(of container: NSPersistentContainer) -> Error? {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = loadError ?? error
        }
        return loadError
    }

    /// Удаляет файлы хранилищ контейнера вместе со служебными файлами SQLite (`-wal`, `-shm`).
    /// Сначала через координатор — он умеет удалять корректное хранилище; файлы, которые он не распознал
    /// (например, повреждённые), удаляются напрямую.
    /// - Parameter container: контейнер, хранилища которого удаляются.
    private static func destroyStores(of container: NSPersistentContainer) {
        for description in container.persistentStoreDescriptions {
            // Хранилище в памяти (`/dev/null`) удалять нечего.
            guard let url = description.url, url != URL(fileURLWithPath: "/dev/null") else { continue }
            try? container.persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: description.type)
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
    }
}

extension NSPersistentContainer {
    /// Выполняет блок в новом фоновом контексте с политикой слияния «новые данные побеждают».
    /// - Parameter block: работа с контекстом; `save()` вызывается внутри блока.
    func performWrite<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            return try block(context)
        }
    }
}
