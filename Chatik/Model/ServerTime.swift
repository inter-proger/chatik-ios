//
//  ServerTime.swift
//  Chatik
//

import Foundation

/// Серверная метка времени — Unix timestamp в миллисекундах. Хранится ровно тем целым, что прислал сервер:
/// значения уходят обратно в фильтры синхронизации со строгим сравнением, и перевод в `Date` и обратно
/// не должен их менять.
struct ServerTime: Comparable, Hashable, Sendable {
    let milliseconds: Int64

    /// Время для отображения.
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// Время, сдвинутое на указанное число миллисекунд.
    /// - Parameter milliseconds: сдвиг; отрицательный — в прошлое.
    func adding(milliseconds: Int64) -> ServerTime {
        ServerTime(milliseconds: self.milliseconds + milliseconds)
    }

    static func < (lhs: ServerTime, rhs: ServerTime) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }
}

extension ServerTime: Decodable {
    /// Разбирает целое число миллисекунд.
    init(from decoder: Decoder) throws {
        milliseconds = try decoder.singleValueContainer().decode(Int64.self)
    }
}

extension ServerTime {
    /// Текущее время устройства — только для превью и локальных заглушек: фильтры синхронизации берут время
    /// из данных сервера, а не из часов устройства.
    static var now: ServerTime {
        ServerTime(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    }
}
