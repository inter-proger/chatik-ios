//
//  ConversationsPage.swift
//  Chatik
//

import Foundation

/// Страница списка переписок — ответ `/conversations/getList`.
struct ConversationsPage: Decodable, Equatable {
    /// Переписки по убыванию `conversationId` — сначала самые новые.
    let conversations: [Conversation]
    /// Есть ли переписки после этой страницы.
    let hasNext: Bool
}

extension ConversationsPage {
    /// Диапазон `conversationId`, который страница покрывает целиком: переписка из этого диапазона, которой
    /// в странице нет, на сервере в списке больше не показывается. Опирается на то, что сервер отдаёт переписки
    /// по убыванию `conversationId`.
    /// - Parameter isFirstPage: `true` — страница первая, и выше её первой переписки на сервере ничего нет.
    /// - Returns: `nil`, если о диапазоне ничего сказать нельзя (пустая не первая страница, нарушен порядок).
    func coveredIdRange(isFirstPage: Bool) -> ClosedRange<Int>? {
        // Порядок проверяется по всей странице, а не по краям: при `[5, 9, 3]` диапазон `3...` задел бы 4, 6, 7, 8,
        // которые могут быть на следующих страницах, и они удалились бы из БД.
        let ids = conversations.map(\.conversationId)
        guard zip(ids, ids.dropFirst()).allSatisfy({ $0 > $1 }) else { return nil }
        let lowerBound = hasNext ? conversations.last?.conversationId : Int.min
        let upperBound = isFirstPage ? Int.max : conversations.first?.conversationId
        guard let lowerBound, let upperBound, lowerBound <= upperBound else { return nil }
        return lowerBound...upperBound
    }
}
