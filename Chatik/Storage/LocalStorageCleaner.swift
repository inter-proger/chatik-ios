//
//  LocalStorageCleaner.swift
//  Chatik
//

import CoreData

protocol LocalStorageCleanerProtocol {
    /// Удаляет записи всех сущностей локальной БД.
    func clearAll() async throws
}

/// Очистка локальной БД при завершении сессии: БД — кэш данных конкретного пользователя, и следующий
/// пользователь на устройстве не должен увидеть чужие переписки.
final class LocalStorageCleaner: LocalStorageCleanerProtocol {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    /// Удаляет записи всех сущностей модели, не перечисляя их вручную: новая сущность очищается автоматически.
    /// Сервисы работают через короткоживущие фоновые контексты, поэтому мержить удаление в другие контексты не нужно.
    func clearAll() async throws {
        let entityNames = container.managedObjectModel.entities.compactMap(\.name)
        try await container.performWrite { context in
            for name in entityNames {
                let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest(entityName: name))
                try context.execute(request)
            }
        }
    }
}
