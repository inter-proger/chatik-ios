//
//  ConversationListFilter.swift
//  Chatik
//

import Foundation

/// Фильтр `/conversations/getList`. Перечисление, а не набор необязательных параметров: недопустимые сочетания
/// (ошибка `1004` — два фильтра сразу, `changedAfter` со сдвигом) собрать нельзя.
enum ConversationListFilter: Equatable, Sendable {
    /// Без фильтра: обычная пагинация сдвигом. `nil` — с начала списка.
    case none(offset: Int?)
    /// Переписки, поднявшиеся строго после метки; сортировка и сдвиг — как без фильтра.
    case positionUpdatedAfter(ServerTime, offset: Int?)
    /// Переписки с `changeVersion` строго больше значения (изменились информация или прочтение), по возрастанию
    /// `changeVersion`; следующая страница — с `changeVersion` последней полученной переписки, без сдвига.
    case changedAfter(Int)
}
