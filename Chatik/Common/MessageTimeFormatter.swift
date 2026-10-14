//
//  MessageTimeFormatter.swift
//  Chatik
//

import Foundation

/// Время сообщения в формате ленты: сегодняшнее — только время, в этом году — день, месяц и время,
/// раньше — ещё и год. Общий для ленты сообщений и списка чатов.
struct MessageTimeFormatter {
    /// Язык форматирования.
    let locale: Locale
    /// Календарь (с часовым поясом), по которому определяется «сегодня».
    let calendar: Calendar
    /// Текущее время.
    let now: Date

    /// Форматирует время.
    /// - Parameter date: время сообщения.
    func string(from date: Date) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .hour().minute()
        guard !calendar.isDate(date, inSameDayAs: now) else { return date.formatted(style) }
        style = style.day().month(.abbreviated)
        guard calendar.isDate(date, equalTo: now, toGranularity: .year) else {
            return date.formatted(style.year())
        }
        return date.formatted(style)
    }
}
