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
        guard let url = modelURL, let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Не найдена модель CoreData Chatik.momd")
        }
        return model
    }()

    private static let modelURL = Bundle(for: UserEntity.self).url(forResource: "Chatik", withExtension: "momd")

    /// Версии модели, в которых серверное время хранилось в секундах (файлы `.mom` внутри `Chatik.momd`).
    /// Хранилище такой версии после миграции очищается от переписок и сообщений: время в них не переводится
    /// в миллисекунды, а данные — только кэш сервера и загрузятся заново.
    private static let secondsModelVersions = ["Chatik", "Chatik 2", "Chatik 3", "Chatik 4", "Chatik 5"]

    /// Сущности с серверным временем, которые очищаются после миграции с версии модели в секундах. Очередь
    /// отправки (`OutgoingMessageEntity`) и пользователи остаются: их время локальное или не серверное.
    private static let serverTimeEntityNames = ["ConversationEntity", "MessageEntity"]

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
        let needsServerTimeCleanup = storesUseSecondsModel(container)
        guard let error = loadStores(of: container) else {
            if needsServerTimeCleanup {
                clearServerTimeEntities(in: container)
            }
            return container
        }

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

    /// `true`, если хранилище контейнера уже существует и создано версией модели, в которой серверное время
    /// хранилось в секундах. Проверяется до открытия: после миграции хранилище уже текущей версии.
    /// - Parameter container: контейнер, хранилища которого ещё не открыты.
    private static func storesUseSecondsModel(_ container: NSPersistentContainer) -> Bool {
        guard let url = container.persistentStoreDescriptions.first?.url,
              url != URL(fileURLWithPath: "/dev/null"),
              FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url) else {
            return false
        }
        // Хранилище текущей версии — обычный запуск: старые модели можно не загружать.
        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return false }
        return secondsModelVersions.contains { version in
            guard let modelURL, let model = NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("\(version).mom")) else {
                return false
            }
            // Классы Entity принадлежат текущей версии модели: прежняя не должна на них претендовать.
            model.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }
            return model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        }
    }

    /// Удаляет переписки и сообщения, мигрированные с версии модели в секундах. Хранилище целиком не пересоздаётся:
    /// пропали бы неотправленные сообщения. Ошибка удаления логируется — устаревший кэш не мешает открыть БД.
    /// - Parameter container: контейнер с открытыми хранилищами.
    private static func clearServerTimeEntities(in container: NSPersistentContainer) {
        let context = container.newBackgroundContext()
        context.performAndWait {
            do {
                for name in serverTimeEntityNames {
                    try context.execute(NSBatchDeleteRequest(fetchRequest: NSFetchRequest(entityName: name)))
                }
            } catch {
                Logger.storage.error("Не удалось очистить кэш со временем в секундах: \(String(describing: error), privacy: .public)")
            }
        }
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
