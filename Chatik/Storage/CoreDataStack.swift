//
//  CoreDataStack.swift
//  Chatik
//

import CoreData
import os

/// Фабрика контейнеров CoreData. Контейнер передаётся в storage-сервисы через `init`
/// (в приложении — из `DIContainer`, открывается в фоне через `BackgroundLoadedContainer`).
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

/// Источник контейнера CoreData для storage-сервисов: готовый контейнер (тесты, превью) или контейнер,
/// хранилища которого открываются в фоне (приложение).
protocol PersistentContainerProvider {
    /// Контейнер с открытыми хранилищами; если открытие ещё идёт — дожидается его.
    func loadedContainer() async -> NSPersistentContainer
}

extension PersistentContainerProvider {
    /// Выполняет блок в новом фоновом контексте.
    /// - Parameter block: чтение из контекста.
    func performRead<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await loadedContainer().performBackgroundTask(block)
    }

    /// Выполняет блок в новом фоновом контексте с политикой слияния «новые данные побеждают».
    /// - Parameter block: работа с контекстом; `save()` вызывается внутри блока.
    func performWrite<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await loadedContainer().performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            return try block(context)
        }
    }
}

/// Контейнер, созданный с уже открытыми хранилищами, отдаёт сам себя.
extension NSPersistentContainer: PersistentContainerProvider {
    func loadedContainer() async -> NSPersistentContainer {
        self
    }
}

/// Контейнер, хранилища которого открываются в фоновой задаче: открытие SQLite (а при сбое — пересоздание
/// хранилища и миграция) не блокирует main при старте приложения. Запросы к БД, пришедшие раньше, дожидаются открытия.
///
/// `@unchecked Sendable`: единственное состояние — задача открытия; контейнер после открытия используется
/// только через `performBackgroundTask`, безопасный для вызова из любого потока.
final class BackgroundLoadedContainer: PersistentContainerProvider, @unchecked Sendable {
    /// Обёртка, чтобы вернуть контейнер из фоновой задачи: `NSPersistentContainer` не объявлен `Sendable`.
    private struct Loaded: @unchecked Sendable {
        let container: NSPersistentContainer
    }

    private let loading: Task<Loaded, Never>

    /// Сразу начинает открывать контейнер в фоне.
    /// - Parameter makeContainer: создаёт контейнер и синхронно открывает его хранилища.
    init(_ makeContainer: @escaping @Sendable () -> NSPersistentContainer) {
        loading = Task.detached(priority: .userInitiated) { Loaded(container: makeContainer()) }
    }

    func loadedContainer() async -> NSPersistentContainer {
        await loading.value.container
    }
}
