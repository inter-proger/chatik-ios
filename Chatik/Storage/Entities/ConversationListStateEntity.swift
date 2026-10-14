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
    @NSManaged var infoWatermark: NSNumber?

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
        infoWatermark = state.infoWatermark.map { NSNumber(value: $0.milliseconds) }
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
            infoWatermark: entity.infoWatermark.map { ServerTime(milliseconds: $0.int64Value) }
        )
    }
}
