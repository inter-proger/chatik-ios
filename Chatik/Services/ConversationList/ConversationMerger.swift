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
    /// Только прочтение: событие `conversations` / `read`, ответ `/conversations/markRead`.
    case read(ReadInfo)

    var conversationId: Int {
        switch self {
        case let .full(conversation): return conversation.conversationId
        case let .patch(patch): return patch.conversationId
        case let .read(readInfo): return readInfo.conversationId
        }
    }
}

/// Итог слияния: новая локальная версия и признак того, что сменилась позиция (строку нужно переместить).
struct ConversationMergeResult: Equatable {
    let conversation: Conversation
    let isPositionChanged: Bool
}

/// Правила слияния переписки. У неё три независимые версии — позиция, информация и прочтение, — поэтому правило
/// «побеждает больший `updatedAt`» не подходит. К каждой пришедшей версии по порядку применяются четыре правила:
///
/// 1. **Позиция.** Пришедшая `ConversationPosition` строго больше локальной → берутся `positionUpdatedAt`
///    и `lastMessage` целиком.
/// 2. **Текст последнего сообщения.** `lastMessage.messageId` совпадает с локальным, а `lastMessage.updatedAt`
///    больше → берётся `lastMessage`.
/// 3. **Информация** (только полный объект). `updatedInfoAt` больше локального → берутся `memberIds`, `name`,
///    `avatar`, `opponentUserId`, `updatedInfoAt`.
/// 4. **Прочтение** (полный объект, `read` и патч с `readInfo`). `changeVersion` строго больше локального → берётся
///    `readState` целиком. Информацию по `changeVersion` не сливают: события `messages` несут версию, но не информацию.
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
        let isPositionChanged = incoming.position.map { $0.version > local.position } ?? false
        if isPositionChanged, let incomingPosition = incoming.position {
            position = incomingPosition
        }
        if let incomingLast = incoming.position?.lastMessage, let localLast = position.lastMessage,
           incomingLast.messageId == localLast.messageId, incomingLast.updatedAt > localLast.updatedAt {
            position.lastMessage = incomingLast
        }
        let info = incoming.info.flatMap { $0.updatedInfoAt > local.updatedInfoAt ? $0 : nil } ?? local
        let readState = incoming.readState.flatMap { $0.changeVersion > local.readState.changeVersion ? $0 : nil }
            ?? local.readState
        let merged = makeConversation(info: info, position: position, readState: readState, base: local)
        guard merged != local else { return nil }
        return ConversationMergeResult(conversation: merged, isPositionChanged: isPositionChanged)
    }

    /// Собирает переписку из информации одной версии, позиции и прочтения других.
    /// - Parameters:
    ///   - info: версия, из которой берётся информация.
    ///   - position: позиция и последнее сообщение.
    ///   - readState: прочтение.
    ///   - base: локальная версия — источник неизменяемых полей.
    private static func makeConversation(
        info: Conversation,
        position: Position,
        readState: ConversationReadState,
        base: Conversation
    ) -> Conversation {
        Conversation(
            conversationId: base.conversationId,
            type: base.type,
            memberIds: info.memberIds,
            name: info.name,
            avatar: info.avatar,
            opponentUserId: info.opponentUserId,
            lastMessage: position.lastMessage,
            positionUpdatedAt: position.positionUpdatedAt,
            updatedInfoAt: info.updatedInfoAt,
            readState: readState
        )
    }

    /// Позиция переписки вместе с последним сообщением.
    private struct Position {
        let positionUpdatedAt: ServerTime
        var lastMessage: LastMessage?

        /// Версия позиции — для правила 1.
        var version: ConversationPosition {
            ConversationPosition(positionUpdatedAt: positionUpdatedAt, messageId: lastMessage?.messageId ?? 0)
        }
    }

    /// Пришедшая версия, разобранная на позицию, информацию (для полного объекта) и прочтение.
    private struct Incoming {
        /// Позиция; `nil` — версия её не несёт (`read`).
        let position: Position?
        /// Полный объект — источник информации; `nil` для патча и прочтения.
        let info: Conversation?
        /// Прочтение; `nil` — версия его не несёт.
        let readState: ConversationReadState?

        init(_ update: ConversationUpdate) {
            switch update {
            case let .full(conversation):
                position = Position(positionUpdatedAt: conversation.positionUpdatedAt, lastMessage: conversation.lastMessage)
                info = conversation
                readState = conversation.readState
            case let .patch(patch):
                position = Position(positionUpdatedAt: patch.positionUpdatedAt, lastMessage: patch.lastMessage)
                info = nil
                readState = patch.readInfo?.readState
            case let .read(readInfo):
                position = nil
                info = nil
                readState = readInfo.readState
            }
        }
    }
}
