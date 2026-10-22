//
//  MessageReadersContent.swift
//  Chatik
//

import Foundation

/// Что показать на листе «Кем прочитано» вместо пустого списка.
enum MessageReadersPlaceholder: Equatable, Sendable {
    /// Указателей прочтения ещё нет: идёт чтение из БД или запрос.
    case loading
    /// Указателей нет, и запрос не удался.
    case failed
    /// Указатели есть, но сообщение никто не прочитал.
    case empty
}

/// Содержимое листа «Кем прочитано» в готовом для отображения виде. Собирается за одно вычисление: заголовок
/// и заглушка выводятся из того же списка строк.
struct MessageReadersContent: Equatable, Sendable {
    let title: String
    /// Строки списка: загруженные участники — по имени, затем ещё не загруженные.
    let readers: [MessageReaderDisplayModel]
    /// `nil` — показывается список.
    let placeholder: MessageReadersPlaceholder?
}
