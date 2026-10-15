//
//  MessageTimeFormatter.swift
//  Chatik
//

import Foundation

/// Время сообщения. Для списка чатов (`string(from:)`): сегодняшнее — только время, в этом году — день, месяц
/// и время, раньше — ещё и год. Для пузыря в ленте (`timeString(from:locale:calendar:)`) — всегда только время:
/// дату показывает заголовок дня, поэтому текущее время ему не нужно. Оба формата строятся на одном стиле времени.
struct MessageTimeFormatter {
    /// Язык форматирования.
    let locale: Locale
    /// Календарь (с часовым поясом), по которому определяется «сегодня».
    let calendar: Calendar
    /// Текущее время.
    let now: Date

    /// Форматирует время для списка чатов.
    /// - Parameter date: время сообщения.
    func string(from date: Date) -> String {
        var style = Self.timeStyle(locale: locale, calendar: calendar)
        guard !calendar.isDate(date, inSameDayAs: now) else { return date.formatted(style) }
        style = style.day().month(.abbreviated)
        guard calendar.isDate(date, equalTo: now, toGranularity: .year) else {
            return date.formatted(style.year())
        }
        return date.formatted(style)
    }

    /// Форматирует только время, без даты: `18:40` в `ru`, `6:40 PM` в `en`.
    /// - Parameters:
    ///   - date: время сообщения.
    ///   - locale: язык форматирования.
    ///   - calendar: календарь с часовым поясом.
    static func timeString(from date: Date, locale: Locale, calendar: Calendar) -> String {
        date.formatted(timeStyle(locale: locale, calendar: calendar))
    }

    /// Часы и минуты; 12- или 24-часовой формат выбирает локаль.
    /// - Parameters:
    ///   - locale: язык форматирования.
    ///   - calendar: календарь с часовым поясом.
    private static func timeStyle(locale: Locale, calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
    }
}
