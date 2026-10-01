//
//  MessagesPage.swift
//  Chatik
//

import Foundation

/// Страница сообщений переписки — ответ `/messages/getList`. Состоит из целых блоков, минимум 40 сообщений,
/// если в переписке их столько есть.
struct MessagesPage: Decodable, Equatable {
    /// Сообщения по убыванию `messageId` — сначала самые новые.
    let messages: [Message]
    /// Первый блок, не попавший в страницу; передаётся в `blockId` за более старыми сообщениями.
    /// `nil`, если более старых сообщений нет.
    let nextBlockId: Int?
    /// Есть ли сообщения старше этой страницы.
    let hasNext: Bool
}
