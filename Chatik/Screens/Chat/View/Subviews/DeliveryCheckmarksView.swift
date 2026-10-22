//
//  DeliveryCheckmarksView.swift
//  Chatik
//

import SwiftUI

/// Галочки своего серверного сообщения в стиле Telegram: одна — доставлено, две — прочитано. Тонкие штрихи
/// со скруглёнными концами; у двух галочек короткий штрих правой обрезан о левую, а не перекрещивает её.
///
/// Одна галочка стоит на месте правой — у края пузыря, без пустоты после себя. При прочтении левая
/// дорисовывается, а короткий штрих правой укорачивается; при «Уменьшении движения» — без анимации.
/// Размер не зависит от состояния (ширина пузыря не меняется) и растёт с Dynamic Type вместе с временем;
/// низ галочек — на базовой линии текста подвала.
struct DeliveryCheckmarksView: View {
    let isRead: Bool

    /// Высота галочек — примерно высота заглавных букв `caption2`.
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DeliveryCheckmarksShape(readProgress: isRead ? 1 : 0)
            .frame(width: height * DeliveryCheckmarksShape.aspectRatio, height: height)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isRead)
    }
}

/// Контур галочек: штрихи уже обведены (`strokedPath`), поэтому фигура заливается цветом текста, как символ.
///
/// Геометрия — в условной системе координат высотой 1 и шириной `aspectRatio`: галочка — короткий штрих
/// `A → B` и длинный `B → C`, правая галочка — та же, сдвинутая на `secondOffset`.
struct DeliveryCheckmarksShape: Shape {
    /// 0 — одна галочка, 1 — две; промежуточные значения — кадры анимации.
    var readProgress: CGFloat

    /// Отношение ширины к высоте.
    static let aspectRatio: CGFloat = check.c.x + secondOffset
    /// Толщина штриха относительно высоты.
    private static let lineWidthRatio: CGFloat = 0.14
    /// Сдвиг правой галочки относительно левой.
    private static let secondOffset: CGFloat = 0.42
    /// Галочка: начало короткого штриха, излом, конец длинного.
    private static let check = (a: CGPoint(x: 0, y: 0.52), b: CGPoint(x: 0.42, y: 1), c: CGPoint(x: 1.2, y: 0))

    var animatableData: CGFloat {
        get { readProgress }
        set { readProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let lineWidth = rect.height * Self.lineWidthRatio
        let inner = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let point = { (unit: CGPoint) in
            CGPoint(x: inner.minX + unit.x / Self.aspectRatio * inner.width, y: inner.minY + unit.y * inner.height)
        }
        var path = Path()
        path.addLines(Self.firstCheck(progress: readProgress).map(point))
        path.addLines(Self.secondCheck(progress: readProgress).map(point))
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// Левая галочка, дорисованная на долю `progress` своей длины.
    /// - Parameter progress: 0 — галочки нет, 1 — целиком.
    /// - Returns: точки ломаной; пусто, пока рисовать нечего.
    static func firstCheck(progress: CGFloat) -> [CGPoint] {
        let points = [check.a, check.b, check.c]
        let lengths = zip(points, points.dropFirst()).map { distance($0, $1) }
        var remaining = lengths.reduce(0, +) * min(max(progress, 0), 1)
        guard remaining > 0 else { return [] }
        var result = [points[0]]
        for (index, length) in lengths.enumerated() {
            guard remaining < length else {
                result.append(points[index + 1])
                remaining -= length
                continue
            }
            result.append(interpolate(points[index], points[index + 1], fraction: remaining / length))
            break
        }
        return result
    }

    /// Правая галочка: короткий штрих укорачивается от полного до точки, где он встречает длинный штрих левой.
    /// - Parameter progress: 0 — штрих полный (одна галочка), 1 — обрезан (две галочки).
    /// - Returns: точки ломаной.
    static func secondCheck(progress: CGFloat) -> [CGPoint] {
        let shift = { (point: CGPoint) in CGPoint(x: point.x + secondOffset, y: point.y) }
        let a = shift(check.a), b = shift(check.b), c = shift(check.c)
        let start = interpolate(a, stubStart(a: a, b: b), fraction: min(max(progress, 0), 1))
        return [start, b, c]
    }

    /// Начало обрезанного короткого штриха правой галочки — пересечение его с длинным штрихом левой.
    /// - Parameters:
    ///   - a: начало полного короткого штриха правой галочки.
    ///   - b: излом правой галочки.
    private static func stubStart(a: CGPoint, b: CGPoint) -> CGPoint {
        // Отрезок b → a и прямая check.b → check.c: b + t·(a − b) = check.b + s·(check.c − check.b).
        let r = CGPoint(x: a.x - b.x, y: a.y - b.y)
        let q = CGPoint(x: check.c.x - check.b.x, y: check.c.y - check.b.y)
        let denominator = r.x * q.y - r.y * q.x
        guard denominator != 0 else { return a }
        let t = ((check.b.x - b.x) * q.y - (check.b.y - b.y) * q.x) / denominator
        return interpolate(b, a, fraction: min(max(t, 0), 1))
    }

    /// Точка на отрезке.
    /// - Parameters:
    ///   - from: начало отрезка.
    ///   - to: конец отрезка.
    ///   - fraction: доля пути от `from` к `to`.
    private static func interpolate(_ from: CGPoint, _ to: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }

    /// Расстояние между точками.
    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .trailing, spacing: 12) {
        ForEach([false, true], id: \.self) { isRead in
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "12:01")
                DeliveryCheckmarksView(isRead: isRead)
            }
        }
    }
    .font(.caption2)
    .foregroundStyle(.white.opacity(0.7))
    .padding()
    .background(Color.outgoingBubble)
}
#endif
