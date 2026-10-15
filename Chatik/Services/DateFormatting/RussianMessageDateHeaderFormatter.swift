//
//  RussianMessageDateHeaderFormatter.swift
//  Chatik
//

import Foundation

/// Заголовок дня для русского языка. Не зависит от версии ICU и гарантирует точный вид заголовков: «Сегодня,
/// 15 октября», «Вторник, 13 октября», «30 декабря 2025 г.».
///
/// Названия месяцев, дней недели и слова «Сегодня», «Вчера», «г.» — языковые данные форматтера, а не тексты
/// интерфейса, поэтому в `.strings` не выносятся: реализация и так существует только для русского.
///
/// Календарь всегда григорианский — с часовым поясом переданного: таблицы месяцев и дней недели написаны для него.
/// Иначе при еврейском календаре устройства (13 месяцев) индекс месяца выходит за массив, а при буддийском год
/// печатается как 2569.
struct RussianMessageDateHeaderFormatter: MessageDateHeaderFormatting {
    let calendar: Calendar

    /// - Parameter calendar: календарь устройства; от него берётся только часовой пояс.
    init(calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
    }

    /// Месяцы в родительном падеже, с января.
    private static let months = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]
    /// Дни недели с заглавной буквы, с воскресенья — как `Calendar.Component.weekday`.
    private static let weekdays = [
        "Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота",
    ]

    /// Форматирует дату заголовка.
    /// - Parameters:
    ///   - date: время любого сообщения этого дня.
    ///   - now: текущее время.
    func string(from date: Date, now: Date) -> String {
        let day = MessageDayClassifier(calendar: calendar).day(of: date, now: now)
        let dayAndMonth = dayAndMonth(of: date, includesYear: day.includesYear)
        switch day.relation {
        case .today:
            return "Сегодня, \(dayAndMonth)"
        case .yesterday:
            return "Вчера, \(dayAndMonth)"
        case .lastWeek:
            return "\(Self.weekdays[calendar.component(.weekday, from: date) - 1]), \(dayAndMonth)"
        case .earlier:
            return dayAndMonth
        }
    }

    /// «15 октября» или «30 декабря 2025 г.».
    /// - Parameters:
    ///   - date: дата.
    ///   - includesYear: нужен ли год.
    private func dayAndMonth(of date: Date, includesYear: Bool) -> String {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        let dayAndMonth = "\(components.day ?? 1) \(Self.months[(components.month ?? 1) - 1])"
        guard includesYear, let year = components.year else { return dayAndMonth }
        return "\(dayAndMonth) \(year) г."
    }
}
