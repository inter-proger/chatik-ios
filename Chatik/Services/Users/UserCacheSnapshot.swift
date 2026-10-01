//
//  UserCacheSnapshot.swift
//  Chatik
//

import Foundation

/// Состояние пользователя с номером изменения в `UserCacheStore`: чем больше номер, тем новее состояние.
struct VersionedUserState: Equatable, Sendable {
    let state: CachedUser
    let revision: UInt64
}

/// Копия состояний пользователей на main actor — то, что экраны читают синхронно и за чем следят через Observation.
/// Источник истины — `UserCacheStore`: он передаёт сюда изменения, а копия только применяет их.
///
/// Изменения из хранилища могут прийти не в том порядке, в каком произошли (между изменением и доставкой
/// у хранилища есть точка ожидания), поэтому применяется только состояние с номером больше уже известного:
/// опоздавшее старое состояние не затирает новое.
@MainActor
@Observable
final class UserCacheSnapshot {
    private var statesById: [Int: VersionedUserState] = [:]

    /// Состояние пользователя; неизвестный — `.pending`.
    /// - Parameter id: идентификатор пользователя.
    func state(id: Int) -> CachedUser {
        statesById[id]?.state ?? .pending
    }

    /// Применяет изменения, которые новее известных. Наблюдатели уведомляются один раз и только если что-то изменилось.
    /// - Parameter states: состояния по id пользователя.
    func apply(_ states: [Int: VersionedUserState]) {
        var updated = statesById
        for (id, state) in states where state.revision > (updated[id]?.revision ?? 0) {
            updated[id] = state
        }
        guard updated != statesById else { return }
        statesById = updated
    }
}
