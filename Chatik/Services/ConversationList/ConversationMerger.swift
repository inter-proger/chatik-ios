//
//  ConversationMerger.swift
//  Chatik
//

import Foundation

/// Пришедшая версия переписки.
enum ConversationUpdate: Equatable {
    /// Полный объект: `getList`, `getBatch`, `createSingle`, событие `singleCreated`.
    case full(Conversation)
    /// Частичная версия: события `received`, `edited`, ответ `/messages/send`.
    case patch(ConversationPatch)

    var conversationId: Int {
        switch self {
        case let .full(conversation): return conversation.conversationId
        case let .patch(patch): return patch.conversationId
        }
    }
}

/// Итог слияния: новая локальная версия и признак того, что сменилась позиция (строку нужно переместить).
struct ConversationMergeResult: Equatable {
    let conversation: Conversation
    let isPositionChanged: Bool
}

/// Правила слияния переписки. У неё две независимые версии — позиция и информация, — поэтому правило
/// «побеждает больший `updatedAt`» не подходит. К каждой пришедшей версии по порядку применяются три правила:
///
/// 1. **Позиция.** Пришедшая `ConversationPosition` строго больше локальной → берутся `positionUpdatedAt`
///    и `lastMessage` целиком.
/// 2. **Текст последнего сообщения.** `lastMessage.messageId` совпадает с локальным, а `lastMessage.updatedAt`
///    больше → берётся `lastMessage`.
/// 3. **Информация** (только полный объект). `updatedInfoAt` больше локального → берутся `memberIds`, `name`,
///    `avatar`, `opponentUserId`, `updatedInfoAt`.
///
/// Повтор той же версии ничего не меняет, поэтому порядок доставки событий не важен.
enum ConversationMerger {
    /// Сливает пришедшую версию с локальной.
    /// - Parameters:
    ///   - update: пришедшая версия той же переписки.
    ///   - local: локальная версия.
    /// - Returns: результат слияния; `nil` — локальная версия не меняется.
    static func merge(_ update: ConversationUpdate, into local: Conversation) -> ConversationMergeResult? {
        let incoming = Incoming(update)
        var position = Position(positionUpdatedAt: local.positionUpdatedAt, lastMessage: local.lastMessage)
        let isPositionChanged = incoming.position > local.position
        if isPositionChanged {
            position = Position(positionUpdatedAt: incoming.positionUpdatedAt, lastMessage: incoming.lastMessage)
        }
        if let incomingLast = incoming.lastMessage, let localLast = position.lastMessage,
           incomingLast.messageId == localLast.messageId, incomingLast.updatedAt > localLast.updatedAt {
            position.lastMessage = incomingLast
        }
        let info = incoming.info.flatMap { $0.updatedInfoAt > local.updatedInfoAt ? $0 : nil } ?? local
        let merged = makeConversation(info: info, position: position, base: local)
        guard merged != local else { return nil }
        return ConversationMergeResult(conversation: merged, isPositionChanged: isPositionChanged)
    }

    /// Собирает переписку из информации одной версии и позиции другой.
    /// - Parameters:
    ///   - info: версия, из которой берётся информация.
    ///   - position: позиция и последнее сообщение.
    ///   - base: локальная версия — источник неизменяемых полей.
    private static func makeConversation(info: Conversation, position: Position, base: Conversation) -> Conversation {
        Conversation(
            conversationId: base.conversationId,
            type: base.type,
            memberIds: info.memberIds,
            name: info.name,
            avatar: info.avatar,
            opponentUserId: info.opponentUserId,
            lastMessage: position.lastMessage,
            positionUpdatedAt: position.positionUpdatedAt,
            updatedInfoAt: info.updatedInfoAt
        )
    }

    /// Позиция переписки вместе с последним сообщением.
    private struct Position {
        let positionUpdatedAt: ServerTime
        var lastMessage: LastMessage?
    }

    /// Пришедшая версия, разобранная на позицию и (для полного объекта) информацию.
    private struct Incoming {
        let positionUpdatedAt: ServerTime
        let lastMessage: LastMessage?
        let position: ConversationPosition
        /// Полный объект — источник информации; `nil` для патча.
        let info: Conversation?

        init(_ update: ConversationUpdate) {
            switch update {
            case let .full(conversation):
                positionUpdatedAt = conversation.positionUpdatedAt
                lastMessage = conversation.lastMessage
                position = conversation.position
                info = conversation
            case let .patch(patch):
                positionUpdatedAt = patch.positionUpdatedAt
                lastMessage = patch.lastMessage
                position = patch.position
                info = nil
            }
        }
    }
}
