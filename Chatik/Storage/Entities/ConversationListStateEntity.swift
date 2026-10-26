//
//  ConversationListStateEntity.swift
//  Chatik
//

import CoreData

/// Единственная запись БД о состоянии синхронизации списка переписок; сырая структура — `ConversationListState`.
@objc(ConversationListStateEntity)
final class ConversationListStateEntity: NSManagedObject {
    @NSManaged var isLoaded: Bool
    @NSManaged var hasMorePages: Bool
    /// Водяные знаки в миллисекундах; `nil` — не заданы.
    @NSManaged var positionWatermark: NSNumber?
    @NSManaged var positionWatermarkCeiling: NSNumber?
    /// Курсор `changedAfter`; `nil` — нужна полная загрузка.
    @NSManaged var syncedChangeVersion: NSNumber?
    @NSManaged var totalUnreadCount: Int64
    @NSManaged var totalUnreadVersion: Int64
    /// `ConversationListState.removedVersions` и `pendingConversations` в JSON (`[String: Int]`); `nil` — пусто.
    @NSManaged var removedVersions: Data?
    @NSManaged var pendingConversations: Data?

    /// Запрос записи состояния. Имя Entity в модели совпадает с именем класса.
    static func makeFetchRequest() -> NSFetchRequest<ConversationListStateEntity> {
        NSFetchRequest<ConversationListStateEntity>(entityName: String(describing: self))
    }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameter state: состояние синхронизации.
    func update(from state: ConversationListState) {
        isLoaded = state.isLoaded
        hasMorePages = state.hasMorePages
        positionWatermark = state.positionWatermark.map { NSNumber(value: $0.milliseconds) }
        positionWatermarkCeiling = state.positionWatermarkCeiling.map { NSNumber(value: $0.milliseconds) }
        syncedChangeVersion = state.syncedChangeVersion.map { NSNumber(value: $0) }
        totalUnreadCount = Int64(state.totalUnreadCount)
        totalUnreadVersion = Int64(state.totalUnreadVersion)
        removedVersions = Self.encode(state.removedVersions)
        pendingConversations = Self.encode(state.pendingConversations)
    }

    /// Кодирует словарь версий в JSON; пустой — `nil`.
    /// - Parameter versions: переписка → версия.
    static func encode(_ versions: [Int: Int]) -> Data? {
        guard !versions.isEmpty else { return nil }
        return try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: versions.map { (String($0.key), $0.value) }))
    }

    /// Разбирает словарь версий из JSON; нет данных или они битые — пусто.
    /// - Parameter data: JSON `[String: Int]`.
    static func decode(_ data: Data?) -> [Int: Int] {
        guard let data, let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    /// Записывает состояние в единственную запись (создаёт её, если её нет), не вызывая `save()`.
    /// - Parameters:
    ///   - state: состояние синхронизации.
    ///   - context: фоновый контекст записи.
    static func store(_ state: ConversationListState, in context: NSManagedObjectContext) throws {
        let entities = try context.fetch(makeFetchRequest())
        let entity = entities.first ?? ConversationListStateEntity(context: context)
        entities.dropFirst().forEach(context.delete)
        entity.update(from: state)
    }
}

extension ConversationListState {
    /// Собирает состояние из записи БД.
    /// - Parameter entity: запись CoreData.
    init(entity: ConversationListStateEntity) {
        self.init(
            isLoaded: entity.isLoaded,
            hasMorePages: entity.hasMorePages,
            positionWatermark: entity.positionWatermark.map { ServerTime(milliseconds: $0.int64Value) },
            positionWatermarkCeiling: entity.positionWatermarkCeiling.map { ServerTime(milliseconds: $0.int64Value) },
            syncedChangeVersion: entity.syncedChangeVersion?.intValue,
            totalUnreadCount: Int(entity.totalUnreadCount),
            totalUnreadVersion: Int(entity.totalUnreadVersion),
            removedVersions: ConversationListStateEntity.decode(entity.removedVersions),
            pendingConversations: ConversationListStateEntity.decode(entity.pendingConversations)
        )
    }
}
