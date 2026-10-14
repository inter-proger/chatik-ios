//
//  MessageBlocksBatch.swift
//  Chatik
//

import Foundation

/// Ответ `/messages/getBlockBatch`.
struct MessageBlocksBatch: Decodable, Equatable, Sendable {
    /// Найденные блоки в порядке запроса.
    let blocks: [MessageBlock]
    /// Несуществующие блоки и блоки переписок, в которых пользователь не состоит, — неотличимы.
    let notFoundIds: [Int]
}
