//
//  MessageDaySectionDisplayModel.swift
//  Chatik
//

import Foundation

/// Идентификатор секции: день и номер его появления в ленте.
struct MessageDaySectionID: Hashable, Sendable {
    /// Начало дня в календаре устройства.
    let day: Date
    /// Номер серии сообщений этого дня, считая от самой старой; обычно 0. Больше нуля — когда день встречается
    /// в ленте ещё раз, например у вчерашнего неотправленного сообщения под сегодняшними.
    let occurrence: Int
}

/// Сообщения одного дня, идущие в ленте подряд, и заголовок над ними.
struct MessageDaySectionDisplayModel: Identifiable, Equatable, Sendable {
    let id: MessageDaySectionID
    /// Текст заголовка, например «Сегодня, 15 октября».
    let title: String
    /// Сообщения, сначала самые новые.
    let messages: [MessageDisplayModel]
}
