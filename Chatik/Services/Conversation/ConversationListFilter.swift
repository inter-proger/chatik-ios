//
//  ConversationListFilter.swift
//  Chatik
//

import Foundation

/// Фильтр `/conversations/getList`. Перечисление, а не набор необязательных параметров: недопустимые сочетания
/// (ошибка `1004` — два фильтра сразу, `updatedInfoAfter` со сдвигом, курсор без фильтра) собрать нельзя.
enum ConversationListFilter: Equatable, Sendable {
    /// Без фильтра: обычная пагинация сдвигом. `nil` — с начала списка.
    case none(offset: Int?)
    /// Переписки, поднявшиеся строго после метки; сортировка и сдвиг — как без фильтра.
    case positionUpdatedAfter(ServerTime, offset: Int?)
    /// Переписки с информацией, изменённой строго после метки, по возрастанию `(updatedInfoAt, conversationId)`;
    /// следующая страница — курсором `afterId` (id последней полученной переписки) вместо сдвига.
    case updatedInfoAfter(ServerTime, afterId: Int?)
}
