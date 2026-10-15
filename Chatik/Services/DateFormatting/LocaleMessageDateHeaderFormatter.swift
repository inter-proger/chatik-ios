//
//  LocaleMessageDateHeaderFormatter.swift
//  Chatik
//

import Foundation

/// Заголовок дня для любого языка — на ICU: падеж, порядок и слова «Сегодня»/«Вчера» берутся из данных локали,
/// строк в `.strings` не нужно. Склейка «<слово>, <день и месяц>» общая для всех языков — если для языка она
/// не подходит, для него пишется отдельная реализация (см. `MessageDateHeaderFormatterProvider`).
struct LocaleMessageDateHeaderFormatter: MessageDateHeaderFormatting {
    let locale: Locale
    let calendar: Calendar
    /// «Сегодня» на языке `locale`; считается один раз — форматтер вызывается на каждую секцию каждой сборки ленты.
    private let today: String
    /// «Вчера» на языке `locale`.
    private let yesterday: String

    /// - Parameters:
    ///   - locale: язык заголовков.
    ///   - calendar: календарь с часовым поясом устройства.
    init(locale: Locale, calendar: Calendar) {
        self.locale = locale
        self.calendar = calendar
        let formatter = Self.makeRelativeFormatter(locale: locale, calendar: calendar)
        today = formatter.localizedString(from: DateComponents(day: 0))
        yesterday = formatter.localizedString(from: DateComponents(day: -1))
    }

    /// Форматирует дату заголовка: «Сегодня, 15 октября», «Вторник, 13 октября», «30 декабря 2025 г.».
    /// - Parameters:
    ///   - date: время любого сообщения этого дня.
    ///   - now: текущее время.
    func string(from date: Date, now: Date) -> String {
        let day = MessageDayClassifier(calendar: calendar).day(of: date, now: now)
        let dayAndMonth = date.formatted(dayAndMonthStyle(includesYear: day.includesYear))
        switch day.relation {
        case .today:
            return "\(today), \(dayAndMonth)"
        case .yesterday:
            return "\(yesterday), \(dayAndMonth)"
        case .lastWeek:
            return date.formatted(dayAndMonthStyle(includesYear: day.includesYear).weekday(.wide))
        case .earlier:
            return dayAndMonth
        }
    }

    /// Стиль «день и месяц» (с годом — по запросу); с заглавной буквы, раз заголовок начинается с него.
    /// - Parameter includesYear: нужен ли год.
    private func dayAndMonthStyle(includesYear: Bool) -> Date.FormatStyle {
        let style = Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone,
            capitalizationContext: .beginningOfSentence
        )
        .day()
        .month(.wide)
        return includesYear ? style.year() : style
    }

    /// Форматтер названий дней относительно сегодняшнего с заглавной буквы: «Сегодня», «Вчера».
    /// - Parameters:
    ///   - locale: язык.
    ///   - calendar: календарь.
    private static func makeRelativeFormatter(locale: Locale, calendar: Calendar) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter
    }
}
