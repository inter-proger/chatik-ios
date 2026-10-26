//
//  MessageReadCoverage.swift
//  Chatik
//

import Foundation

/// Сообщения, прочитанные хотя бы одним другим участником, — отсортированные непересекающиеся полуинтервалы
/// `(after, upTo]` по `messageId` (`docs/group-chats.md`, решение 7). В личной переписке это один интервал
/// `(0, max(указатели)]`; в группе — по интервалу `(joinedAfterMessageId, указатель]` на участника: сообщения до его
/// вступления им не прочитаны, хотя указатель новичка сервер ставит на последнее сообщение группы.
struct MessageReadCoverage: Equatable, Sendable {
    /// Полуинтервал `(after, upTo]`.
    struct Range: Equatable, Sendable {
        let after: Int
        let upTo: Int
    }

    /// Интервалы по возрастанию, без пересечений и стыков.
    let ranges: [Range]

    /// Склеивает интервалы; пустые (`upTo <= after`) отбрасываются.
    /// - Parameter ranges: интервалы в любом порядке.
    init(_ ranges: [Range]) {
        var merged: [Range] = []
        for range in ranges.filter({ $0.upTo > $0.after }).sorted(by: { $0.after < $1.after }) {
            guard let last = merged.last, range.after <= last.upTo else {
                merged.append(range)
                continue
            }
            merged[merged.count - 1] = Range(after: last.after, upTo: max(last.upTo, range.upTo))
        }
        self.ranges = merged
    }

    /// Прочитано ли сообщение хотя бы одним участником.
    /// - Parameter messageId: сообщение.
    func contains(_ messageId: Int) -> Bool {
        ranges.contains { $0.after < messageId && messageId <= $0.upTo }
    }

    /// Покрытие личной переписки: всё до наибольшего указателя.
    /// - Parameter upTo: наибольший указатель.
    static func single(upTo: Int) -> MessageReadCoverage {
        MessageReadCoverage([Range(after: 0, upTo: upTo)])
    }
}
