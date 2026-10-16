//
//  LocalStorageCleaner.swift
//  Chatik
//

import CoreData

protocol LocalStorageCleanerProtocol {
    /// Удаляет записи всех сущностей локальной БД, кроме черновиков сообщений.
    func clearAll() async throws
}

/// Очистка локальной БД при завершении и открытии сессии. БД — кэш серверных данных конкретного пользователя,
/// и следующий пользователь на устройстве не должен увидеть чужие переписки, плюс черновики сообщений: их нет
/// на сервере, поэтому они переживают выход, а чужие черновики скрывает ключ `userId` в записи.
final class LocalStorageCleaner: LocalStorageCleanerProtocol {
    /// Сущности, которые очистка не трогает. Явный список, а не признак в модели: так в одном месте видно,
    /// что переживает выход.
    static let preservedEntityNames: Set<String> = [MessageDraftEntity.entityName]

    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Удаляет записи всех сущностей модели, кроме `preservedEntityNames`, не перечисляя их вручную: новая сущность
    /// очищается автоматически. Сервисы работают через короткоживущие фоновые контексты, поэтому мержить удаление
    /// в другие контексты не нужно.
    func clearAll() async throws {
        let loaded = await container.loadedContainer()
        let entityNames = loaded.managedObjectModel.entities.compactMap(\.name).filter { !Self.preservedEntityNames.contains($0) }
        try await loaded.performWrite { context in
            for name in entityNames {
                let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest(entityName: name))
                try context.execute(request)
            }
        }
    }
}
