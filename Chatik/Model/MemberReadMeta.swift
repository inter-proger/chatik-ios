//
//  MemberReadMeta.swift
//  Chatik
//

import Foundation

/// Указатель прочтения другого участника переписки: всё с id не больше `lastReadMessageId` им прочитано.
/// Версии нет: указатель только растёт, из нескольких значений для участника берётся максимум.
struct MemberReadMeta: Decodable, Hashable, Sendable {
    let userId: Int
    /// Последнее прочитанное участником сообщение; `0` — ничего не прочитано.
    let lastReadMessageId: Int
}

/// Ответ `GET /conversations/getMembersReadMeta`: указатели всех участников, кроме текущего пользователя.
struct MembersReadMetaResponse: Decodable, Equatable {
    let membersReadMeta: [MemberReadMeta]
}
