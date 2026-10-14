//
//  MessageCacheState.swift
//  Chatik
//

import Foundation

/// Состояние кэша сообщений одной переписки. Переписка без такой записи считается «без кэша», даже если в БД
/// есть её сообщения: её первая синхронизация заменяет всё, что лежит в БД.
struct MessageCacheState: Equatable, Sendable {
    /// Отметка синхронизации: максимум `createdAt` / `updatedAt` полученных сообщений и `updatedAt` блоков.
    /// Только время сервера.
    let syncMark: ServerTime
    /// Блок, с которого продолжить подгрузку более старых сообщений с сервера; `nil` — продолжать не с чего.
    let nextBlockId: Int?
    /// Есть ли на сервере сообщения старше кэша.
    let hasMorePages: Bool
}
