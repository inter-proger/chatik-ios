//
//  MessageListFilter.swift
//  Chatik
//

import Foundation

/// Режим `/messages/getList`. Перечисление, а не набор необязательных параметров: `receivedAfter` вместе
/// с `blockId` (ошибка `1004`) собрать нельзя.
enum MessageListFilter: Equatable, Sendable {
    /// Обычная пагинация: блок, с которого начать (включительно); `nil` — с самого нового блока.
    case block(Int?)
    /// Синхронизация кэша: сообщения, присланные строго после метки, и изменённые после неё блоки.
    case receivedAfter(ServerTime)
}
