//
//  StorageEntity.swift
//  Chatik
//

import CoreData

/// Entity с целочисленным серверным идентификатором: общие для всех storage-сервисов выборка по `id`
/// и сохранение (upsert) списка записей.
protocol StorageEntity: NSManagedObject {
    /// Имя атрибута-идентификатора в модели (`userId`, `fileId`, ...).
    static var idKey: String { get }
    /// Серверный идентификатор записи.
    var storageId: Int { get }
}

extension StorageEntity {
    /// Запрос всех записей Entity. Имя Entity в модели совпадает с именем класса.
    static func makeFetchRequest() -> NSFetchRequest<Self> {
        NSFetchRequest<Self>(entityName: String(describing: self))
    }

    /// Запрос одной записи с указанным идентификатором.
    /// - Parameter id: серверный идентификатор записи.
    static func makeFetchRequest(id: Int) -> NSFetchRequest<Self> {
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "%K == %lld", idKey, Int64(id))
        request.fetchLimit = 1
        return request
    }

    /// Достаёт одним запросом существующие записи с переданными идентификаторами.
    /// - Parameters:
    ///   - ids: идентификаторы искомых записей.
    ///   - context: контекст, в котором выполняется запрос.
    /// - Returns: словарь `id → Entity`.
    static func fetchById(ids: [Int], in context: NSManagedObjectContext) throws -> [Int: Self] {
        guard !ids.isEmpty else { return [:] }
        let request = makeFetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", idKey, ids.map { Int64($0) })
        let pairs = try context.fetch(request).map { ($0.storageId, $0) }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// Сохраняет элементы в контексте: запись с тем же идентификатором обновляется, иначе создаётся.
    /// Существующие записи достаются одним запросом; повторы идентификатора в списке схлопываются в одну запись
    /// с данными последнего элемента. `context.save()` не вызывается — это делает владелец контекста.
    /// - Parameters:
    ///   - items: сырые структуры.
    ///   - id: идентификатор структуры.
    ///   - context: фоновый контекст записи.
    ///   - update: переносит поля структуры в Entity.
    /// - Returns: словарь `id → Entity` для всех переданных элементов — чтобы проставить связи.
    static func upsert<Item>(
        _ items: [Item],
        id: (Item) -> Int,
        in context: NSManagedObjectContext,
        update: (Self, Item) -> Void
    ) throws -> [Int: Self] {
        var entitiesById = try fetchById(ids: items.map(id), in: context)
        for item in items {
            let entity = entitiesById[id(item)] ?? Self(context: context)
            update(entity, item)
            entitiesById[id(item)] = entity
        }
        return entitiesById
    }
}
