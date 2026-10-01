//
//  UsersBatch.swift
//  Chatik
//

import Foundation

/// Пользователи по списку id — ответ `/users/getBatch`.
struct UsersBatch: Decodable, Equatable {
    /// Найденные пользователи в порядке запрошенных id.
    let users: [User]
    /// Id, для которых пользователь не найден, в порядке запрошенных id. Повторно их запрашивать незачем.
    let notFoundIds: [Int]
}
