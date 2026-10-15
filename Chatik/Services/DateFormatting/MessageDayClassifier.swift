//
//  MessageDayClassifier.swift
//  Chatik
//

import Foundation

/// Положение дня сообщения относительно текущего дня.
enum MessageDayRelation: Equatable, Sendable {
    case today
    case yesterday
    /// 2–6 дней назад: в заголовке есть день недели.
    case lastWeek
    /// 7 и больше дней назад или дата в будущем.
    case earlier
}

/// День сообщения для заголовка: как он соотносится с сегодняшним и нужен ли год.
struct MessageDay: Equatable, Sendable {
    let relation: MessageDayRelation
    /// `true` — день не в текущем году, в заголовке нужен год.
    let includesYear: Bool
}

/// Определяет, к какому дню относится сообщение, по календарным дням календаря устройства. Правила заголовков
/// дат (сегодня, вчера, последняя неделя, год) живут только здесь — реализации форматтеров их не повторяют.
struct MessageDayClassifier: Sendable {
    let calendar: Calendar

    /// Классифицирует день сообщения.
    /// - Parameters:
    ///   - date: время сообщения.
    ///   - now: текущее время.
    func day(of date: Date, now: Date) -> MessageDay {
        // Считаются полуночи между днями, а не секунды: из-за перехода на летнее время в сутках бывает 23 или 25 часов.
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return MessageDay(
            relation: Self.relation(days: days),
            includesYear: !calendar.isDate(date, equalTo: now, toGranularity: .year)
        )
    }

    /// Положение дня по числу полуночей до текущего дня.
    /// - Parameter days: число полуночей; отрицательное — дата в будущем.
    private static func relation(days: Int) -> MessageDayRelation {
        switch days {
        case 0: return .today
        case 1: return .yesterday
        case 2...6: return .lastWeek
        default: return .earlier
        }
    }
}
