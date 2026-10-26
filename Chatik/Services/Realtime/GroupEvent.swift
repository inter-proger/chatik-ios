//
//  GroupEvent.swift
//  Chatik
//

import Foundation

/// Событие группы `groups` / `*`. Что в теле, зависит от получателя: создатель получает переписку, добавленный —
/// ссылку с версией для курсора, удалённый или вышедший — метку удаления, остальные участники — новый состав.
enum GroupEvent: Equatable, Sendable {
    /// `created` — группа создана текущим пользователем (приходит во все его соединения).
    case created(Conversation, GroupInfo)
    /// `membersAdded`; `changeVersion` не `nil` — добавили текущего пользователя (версия для курсора).
    case membersAdded(conversationId: Int, addedUserIds: [Int], groupInfo: GroupInfo, changeVersion: Int?)
    /// `membersRemoved`; `removal` не `nil` — удалили текущего пользователя, иначе есть `groupInfo`.
    case membersRemoved(conversationId: Int, removedUserIds: [Int], groupInfo: GroupInfo?, removal: ConversationRemoval?)
    /// `memberLeft`; `removal` не `nil` — вышел текущий пользователь, иначе есть `groupInfo`.
    case memberLeft(conversationId: Int, leftUserId: Int, groupInfo: GroupInfo?, removal: ConversationRemoval?)
    /// `ownerChanged` — владение передано.
    case ownerChanged(conversationId: Int, newOwnerUserId: Int, groupInfo: GroupInfo)

    /// Группа события.
    var conversationId: Int {
        switch self {
        case let .created(conversation, _): conversation.conversationId
        case let .membersAdded(conversationId, _, _, _),
             let .membersRemoved(conversationId, _, _, _),
             let .memberLeft(conversationId, _, _, _),
             let .ownerChanged(conversationId, _, _):
            conversationId
        }
    }

    /// Новый состав группы, если событие его несёт.
    var groupInfo: GroupInfo? {
        switch self {
        case let .created(_, info), let .membersAdded(_, _, info, _), let .ownerChanged(_, _, info): info
        case let .membersRemoved(_, _, info, _), let .memberLeft(_, _, info, _): info
        }
    }

    /// Метка удаления текущего пользователя, если событие о нём.
    var removal: ConversationRemoval? {
        switch self {
        case let .membersRemoved(_, _, _, removal), let .memberLeft(_, _, _, removal): removal
        case .created, .membersAdded, .ownerChanged: nil
        }
    }
}

/// Разбор тел событий `groups` из JSON.
enum GroupEventDecoding {
    private struct CreatedBody: Decodable {
        let conversation: Conversation
        let groupInfo: GroupInfo
    }

    private struct MembersAddedBody: Decodable {
        let conversationId: Int
        let addedUserIds: [Int]
        let groupInfo: GroupInfo
        let changeVersion: Int?
    }

    private struct RemovalBody: Decodable {
        let conversationId: Int
        let removedUserIds: [Int]?
        let leftUserId: Int?
        let groupInfo: GroupInfo?
        let removedConversation: RemovedConversation?
        let totalUnreadCount: Int?

        /// Метка вместе со счётчиком; без счётчика метка неполная — событие считается событием для других.
        var removal: ConversationRemoval? {
            guard let removedConversation, let totalUnreadCount else { return nil }
            return ConversationRemoval(removedConversation: removedConversation, totalUnreadCount: totalUnreadCount)
        }

        /// Тело валидно, только если несёт что-то одно из двух: состав (для оставшихся) или метку (для ушедшего).
        var isValid: Bool {
            (groupInfo != nil) != (removal != nil)
        }
    }

    private struct OwnerChangedBody: Decodable {
        let conversationId: Int
        let newOwnerUserId: Int
        let groupInfo: GroupInfo
    }

    /// Разбирает тело события группы.
    /// - Parameters:
    ///   - event: имя события.
    ///   - decode: разбор тела в указанный тип.
    /// - Returns: `nil` — событие неизвестно или тело не разобралось.
    static func decode(event: String, body decode: (any Decodable.Type) -> Any?) -> GroupEvent? {
        switch event {
        case "created":
            return (decode(CreatedBody.self) as? CreatedBody).map { .created($0.conversation, $0.groupInfo) }
        case "membersAdded":
            return (decode(MembersAddedBody.self) as? MembersAddedBody).map {
                .membersAdded(conversationId: $0.conversationId, addedUserIds: $0.addedUserIds, groupInfo: $0.groupInfo, changeVersion: $0.changeVersion)
            }
        case "membersRemoved":
            guard let body = decode(RemovalBody.self) as? RemovalBody, body.isValid, let removed = body.removedUserIds else { return nil }
            return .membersRemoved(conversationId: body.conversationId, removedUserIds: removed, groupInfo: body.groupInfo, removal: body.removal)
        case "memberLeft":
            guard let body = decode(RemovalBody.self) as? RemovalBody, body.isValid, let left = body.leftUserId else { return nil }
            return .memberLeft(conversationId: body.conversationId, leftUserId: left, groupInfo: body.groupInfo, removal: body.removal)
        case "ownerChanged":
            return (decode(OwnerChangedBody.self) as? OwnerChangedBody).map {
                .ownerChanged(conversationId: $0.conversationId, newOwnerUserId: $0.newOwnerUserId, groupInfo: $0.groupInfo)
            }
        default:
            return nil
        }
    }
}
