//
//  MessageCacheStateEntity.swift
//  Chatik
//

import CoreData

/// Запись БД о состоянии кэша сообщений одной переписки; сырая структура — `MessageCacheState`.
@objc(MessageCacheStateEntity)
final class MessageCacheStateEntity: NSManagedObject, StorageEntity {
    @NSManaged var conversationId: Int64
    /// Отметка синхронизации в миллисекундах.
    @NSManaged var syncMark: Int64
    /// `nil` — продолжать подгрузку не с чего.
    @NSManaged var nextBlockId: NSNumber?
    @NSManaged var hasMorePages: Bool

    static let idKey = "conversationId"

    var storageId: Int { Int(conversationId) }

    /// Переносит поля сырой структуры в Entity.
    /// - Parameters:
    ///   - state: состояние кэша.
    ///   - conversationId: переписка.
    func update(from state: MessageCacheState, conversationId: Int) {
        self.conversationId = Int64(conversationId)
        syncMark = state.syncMark.milliseconds
        nextBlockId = state.nextBlockId.map { NSNumber(value: Int64($0)) }
        hasMorePages = state.hasMorePages
    }
}

extension MessageCacheState {
    /// Собирает состояние из записи БД.
    /// - Parameter entity: запись CoreData.
    init(entity: MessageCacheStateEntity) {
        self.init(
            syncMark: ServerTime(milliseconds: entity.syncMark),
            nextBlockId: entity.nextBlockId.map { Int($0.int64Value) },
            hasMorePages: entity.hasMorePages
        )
    }
}
