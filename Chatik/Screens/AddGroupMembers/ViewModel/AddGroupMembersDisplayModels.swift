//
//  AddGroupMembersDisplayModels.swift
//  Chatik
//

import Foundation

/// Фильтр списка пользователей.
enum AddGroupMembersFilter: Hashable, CaseIterable {
    case all
    case notInGroup
}

/// Строка пользователя на экране добавления.
struct AddMemberRowDisplayModel: Identifiable, Equatable {
    let user: UserRowDisplayModel
    /// Уже в группе: отмечен и не выбирается.
    let isMember: Bool
    let isSelected: Bool
    /// Нельзя выбрать: уже в группе или выбрано столько, сколько помещается.
    let isDisabled: Bool

    var id: Int { user.id }
}

/// Не добавленные последним запросом — данные попапа (`docs/group-chats.md`, решение 14).
struct NotAddedReport: Identifiable, Equatable {
    let id = UUID()
    /// Не добавленные в порядке ответа.
    let users: [UserErrorInfo]

    /// Группы по коду ошибки в порядке первого появления.
    var groups: [(errorCode: Int, userIds: [Int])] {
        var order: [Int] = []
        var byCode: [Int: [Int]] = [:]
        for info in users {
            if byCode[info.errorCode] == nil {
                order.append(info.errorCode)
            }
            byCode[info.errorCode, default: []].append(info.userId)
        }
        return order.map { ($0, byCode[$0] ?? []) }
    }

    static func == (lhs: NotAddedReport, rhs: NotAddedReport) -> Bool {
        lhs.id == rhs.id
    }
}

/// Секция попапа не добавленных: причина и пользователи.
struct NotAddedSectionDisplayModel: Identifiable, Equatable {
    let id: Int
    let reason: String
    let users: [GroupMemberDisplayModel]
}
