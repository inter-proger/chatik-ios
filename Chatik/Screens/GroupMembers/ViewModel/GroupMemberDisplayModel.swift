//
//  GroupMemberDisplayModel.swift
//  Chatik
//

import Foundation

/// Пользователь в списке группы (участники, не добавленные) в готовом для отображения виде.
struct GroupMemberDisplayModel: Identifiable, Equatable, Sendable {
    /// Идентификатор пользователя.
    let id: Int
    let name: String
    /// `true` — пользователь ещё не загружен: вместо `name` показывается заглушка.
    let isPlaceholder: Bool
    /// Уменьшенная копия аватара; `nil` — изображение по умолчанию.
    let avatarURL: URL?
    /// Это текущий пользователь — подписан «Вы».
    let isCurrentUser: Bool
}

extension GroupMemberDisplayModel {
    /// Собирает строку по состоянию пользователя в кэше — с теми же текстами, что у отправителей в ленте.
    /// - Parameters:
    ///   - userId: пользователь.
    ///   - cachedUser: пользователь из кэша.
    ///   - isCurrentUser: это текущий пользователь.
    @MainActor
    init(userId: Int, cachedUser: CachedUser, isCurrentUser: Bool = false) {
        let sender = MessageSenderDisplayModel(cachedUser: cachedUser, strings: .current)
        self.init(id: userId, name: sender.name, isPlaceholder: sender.isPlaceholder, avatarURL: sender.avatarURL, isCurrentUser: isCurrentUser)
    }

    /// Порядок строк: загруженные раньше заглушек, внутри — по имени, при равных именах — по id.
    /// - Parameters:
    ///   - lhs: первая строка.
    ///   - rhs: вторая строка.
    static func isOrderedBefore(_ lhs: GroupMemberDisplayModel, _ rhs: GroupMemberDisplayModel) -> Bool {
        guard lhs.isPlaceholder == rhs.isPlaceholder else { return !lhs.isPlaceholder }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}
