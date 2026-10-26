//
//  GroupInfo.swift
//  Chatik
//

import Foundation

/// Объект `GroupInfo` из API — состав и роли группы. В `Conversation` группы его нет: он запрашивается при открытии
/// группы (`/groups/getInfo`) и обновляется событиями `groups`. Пришедшая версия заменяет локальную целиком, только
/// если её `version` больше.
struct GroupInfo: Codable, Hashable, Sendable {
    let conversationId: Int
    /// Растёт при каждом изменении состава или владельца; своя у каждой группы.
    let version: Int
    /// Все участники, включая владельца, по возрастанию `userId`.
    let members: [GroupMember]

    /// Участник по id; `nil` — не состоит в группе.
    /// - Parameter userId: идентификатор пользователя.
    func member(userId: Int) -> GroupMember? {
        members.first { $0.userId == userId }
    }

    /// Владелец группы; `nil` — в данных его нет (не должно случаться).
    var owner: GroupMember? {
        members.first { $0.role == .owner }
    }
}

/// Объект `GroupMember` из API — участник группы.
struct GroupMember: Codable, Hashable, Sendable {
    let userId: Int
    let role: GroupRole
    /// Последнее сообщение группы на момент вступления (`0` — до первого сообщения). Участник учитывается
    /// в статусе «прочитано» только у сообщений с большим `messageId`.
    let joinedAfterMessageId: Int
}

/// Роль участника группы. Список будет расширяться (модераторы): неизвестная роль читается как `.member` — так
/// требует сервер. Права экраны проверяют свойствами роли, а не сравнением с `.owner`.
enum GroupRole: String, Codable, Hashable, Sendable {
    case owner
    case member

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = GroupRole(rawValue: rawValue) ?? .member
    }

    /// Может ли приглашать участников в группу.
    var canAddMembers: Bool {
        self == .owner
    }

    /// Может ли передать права создателя другому участнику.
    var canTransferOwnership: Bool {
        self == .owner
    }

    /// Может ли исключать участников из группы.
    var canRemoveMembers: Bool {
        self == .owner
    }
}

/// Объект `RemovedConversation` из API — метка: текущий пользователь перестал быть участником переписки (удалён
/// из группы или вышел) на версии `changeVersion`.
struct RemovedConversation: Codable, Hashable, Sendable {
    let conversationId: Int
    let changeVersion: Int
}

/// Метка удаления вместе с общим счётчиком непрочитанных на её версии — так они приходят в событиях
/// `membersRemoved` / `memberLeft` и в ответе `/groups/leave`.
struct ConversationRemoval: Decodable, Hashable, Sendable {
    let removedConversation: RemovedConversation
    let totalUnreadCount: Int
}

/// Объект `UserErrorInfo` из API — пользователь, по которому действие не выполнено, и причина (код из `Errors.md`).
struct UserErrorInfo: Decodable, Hashable, Sendable {
    let userId: Int
    let errorCode: Int
}

/// Ответ `/groups/addMembers`.
struct AddMembersResult: Decodable, Equatable, Sendable {
    /// Добавленные, в порядке запроса.
    let addedUserIds: [Int]
    /// Не добавленные с причиной, в порядке запроса.
    let notAddedUsersInfo: [UserErrorInfo]
    /// Состав после изменения.
    let groupInfo: GroupInfo
}

/// Ответ `/groups/removeMembers`.
struct RemoveMembersResult: Decodable, Equatable, Sendable {
    /// Исключённые, в порядке запроса.
    let removedUserIds: [Int]
    /// Не исключённые с причиной (`5007` — не участник, `5008` — владелец), в порядке запроса.
    let notRemovedUsersInfo: [UserErrorInfo]
    /// Состав после изменения.
    let groupInfo: GroupInfo
}

/// Ответ `/groups/create`.
struct CreatedGroup: Decodable, Equatable, Sendable {
    let conversation: Conversation
    let groupInfo: GroupInfo
}

/// Ответ `/groups/getInfo` и `/groups/changeOwner`: `{ "groupInfo": { ... } }`.
struct GroupInfoResponse: Decodable, Equatable {
    let groupInfo: GroupInfo
}

/// Лимиты групп сервера — единственный владелец этих чисел.
enum GroupLimits {
    /// Участников в группе, включая владельца.
    static let maxMembers = 100
    /// Длина названия после обрезки, в кодовых точках Unicode.
    static let nameMaxLength = 128
    /// Длина описания после обрезки, в кодовых точках Unicode.
    static let descriptionMaxLength = 1024
}
