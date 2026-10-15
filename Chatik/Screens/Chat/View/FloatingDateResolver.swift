//
//  FloatingDateResolver.swift
//  Chatik
//

import CoreGraphics

/// Строка ленты, за кадром которой следит трекер плавающей даты.
struct FloatingDateRow: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case message(MessageClientKey)
        case header
    }

    let kind: Kind
    /// Секция, к которой относится строка.
    let section: MessageDaySectionID
}

/// Дата для плавающей плашки: верхняя секция и её заголовок.
struct FloatingDate: Equatable, Sendable {
    let section: MessageDaySectionID
    let title: String
}

/// Выбирает, какую дату показать на плавающей плашке, — чистая функция геометрии ленты.
enum FloatingDateResolver {
    /// Допуск сравнения с линией: дробные координаты раскладки не должны переключать плашку туда и обратно.
    static let tolerance: CGFloat = 0.5

    /// Дата верхней секции, если её заголовок не дошёл до своего места под плашкой.
    ///
    /// Верхняя секция — секция строки, которая пересекает линию плашки или первой лежит под ней. Её заголовок
    /// «на месте», если он выложен и его верх не выше линии: тогда плашка не нужна.
    /// - Parameters:
    /// Вызывается на каждое изменение кадра строки, поэтому — один проход без промежуточных массивов, а заголовок
    /// ищется по ключу.
    /// - Parameters:
    ///   - rows: визуальные кадры выложенных строк.
    ///   - titles: заголовки секций.
    ///   - line: линия плашки — верх плашки в координатах ленты.
    /// - Returns: секция и заголовок для плашки; `nil` — плашка не нужна или строк нет.
    static func resolve(
        rows: [FloatingDateRow: CGRect],
        titles: [MessageDaySectionID: String],
        line: CGFloat
    ) -> FloatingDate? {
        guard let section = topSection(rows: rows, line: line) else { return nil }
        let header = rows[FloatingDateRow(kind: .header, section: section)]
        guard header.map({ $0.minY < line - tolerance }) ?? true, let title = titles[section] else { return nil }
        return FloatingDate(section: section, title: title)
    }

    /// Секция самой верхней строки из тех, что пересекают линию или лежат под ней.
    /// - Parameters:
    ///   - rows: визуальные кадры выложенных строк.
    ///   - line: линия плашки.
    private static func topSection(rows: [FloatingDateRow: CGRect], line: CGFloat) -> MessageDaySectionID? {
        var top: (section: MessageDaySectionID, minY: CGFloat)?
        for (row, frame) in rows where frame.maxY > line {
            guard top.map({ frame.minY < $0.minY }) ?? true else { continue }
            top = (row.section, frame.minY)
        }
        return top?.section
    }
}
