//
//  Calendar+Stub.swift
//  ChatikTests
//

import Foundation

extension Calendar {
    /// Григорианский календарь с фиксированным часовым поясом — тесты не зависят от настроек устройства.
    /// - Parameter timeZone: идентификатор часового пояса; по умолчанию — `Europe/Moscow`.
    static func stub(timeZone: String = "Europe/Moscow") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    /// Момент времени в часовом поясе календаря.
    /// - Parameters:
    ///   - year: год.
    ///   - month: месяц.
    ///   - day: день.
    ///   - hour: час; по умолчанию — полдень.
    ///   - minute: минута.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
